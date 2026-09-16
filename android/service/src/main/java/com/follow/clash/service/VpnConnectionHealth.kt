package com.follow.clash.service

import android.net.Network
import com.follow.clash.common.GlobalState
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal interface VpnHealthSignalSink {
    fun onUnderlyingNetworkChanged(
        network: Network?,
        validated: Boolean,
        description: String,
    )

    fun onDeviceSuspensionChanged(suspended: Boolean)
}

internal enum class VpnRecoveryAction {
    NONE,
    REBUILD_TUN,
    STUCK,
}

internal data class VpnHealthDecision(
    val action: VpnRecoveryAction,
    val consecutiveFailures: Int,
)

/**
 * Pure recovery policy: a single slow request never rebuilds the tunnel. Three consecutive
 * data-plane failures trigger one local TUN rebuild. If the rebuilt tunnel still fails three times,
 * stop churning and leave a clear diagnostic breadcrumb for the next recovery layer.
 */
internal class VpnHealthRecoveryPolicy(
    private val failuresBeforeRecovery: Int = 3,
) {
    private var consecutiveFailures = 0
    private var tunRecoveryAttempted = false
    private var stuckReported = false

    init {
        require(failuresBeforeRecovery > 0)
    }

    fun onSuccess(): Boolean {
        val hadProblem = consecutiveFailures > 0 || tunRecoveryAttempted || stuckReported
        reset()
        return hadProblem
    }

    fun onNetworkChanged() = reset()

    fun onFailure(): VpnHealthDecision {
        consecutiveFailures++
        if (consecutiveFailures < failuresBeforeRecovery) {
            return VpnHealthDecision(VpnRecoveryAction.NONE, consecutiveFailures)
        }

        val count = consecutiveFailures
        consecutiveFailures = 0
        if (!tunRecoveryAttempted) {
            tunRecoveryAttempted = true
            return VpnHealthDecision(VpnRecoveryAction.REBUILD_TUN, count)
        }
        if (!stuckReported) {
            stuckReported = true
            return VpnHealthDecision(VpnRecoveryAction.STUCK, count)
        }
        return VpnHealthDecision(VpnRecoveryAction.NONE, count)
    }

    private fun reset() {
        consecutiveFailures = 0
        tunRecoveryAttempted = false
        stuckReported = false
    }
}

private data class HealthSnapshot(
    val generation: Long,
    val underlyingNetwork: Network?,
    val underlyingValidated: Boolean,
    val underlyingDescription: String,
)

private data class HealthProbeResult(
    val healthy: Boolean,
    val detail: String,
)

/**
 * Verifies the actual VPN data path rather than process liveness. It only probes after meaningful
 * lifecycle events (start, underlying-network change, resume) and retries after a failure; there is
 * no permanent polling loop and no wakelock.
 *
 * A wake or network transition first gets a bounded readiness window. Once Android reports a real
 * validated non-VPN network, stale Core sessions are reset before probing. This keeps recovery cheap
 * in the common case while still retaining the bounded TUN rebuild for a genuinely dead data path.
 */
internal class VpnConnectionHealth(private val service: VpnService) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val probeMutex = Mutex()
    private val policy = VpnHealthRecoveryPolicy()
    private val stateLock = Any()

    private var generation = 0L
    private var underlyingNetwork: Network? = null
    private var underlyingValidated = false
    private var underlyingDescription = "none"
    private var suspended = false
    private var stopped = false
    private val jobs = mutableSetOf<Job>()

    fun start(
        network: Network?,
        validated: Boolean,
        description: String,
        suspended: Boolean,
    ) {
        synchronized(stateLock) {
            if (stopped) return
            generation++
            underlyingNetwork = network
            underlyingValidated = validated
            underlyingDescription = description
            this.suspended = suspended
            policy.onNetworkChanged()
        }
        scheduleProbe(
            reason = "start",
            delayMillis = START_PROBE_DELAY_MILLIS,
            waitForNetwork = true,
        )
    }

    fun onUnderlyingNetworkChanged(
        network: Network?,
        validated: Boolean,
        description: String,
    ) {
        val shouldResetConnections = synchronized(stateLock) {
            if (stopped) return
            val previousNetwork = underlyingNetwork
            val wasValidated = underlyingValidated
            generation++
            underlyingNetwork = network
            underlyingValidated = validated
            underlyingDescription = description
            policy.onNetworkChanged()
            validated && network != null && (network != previousNetwork || !wasValidated)
        }
        GlobalState.log(
            "VPN health: underlying=$description network=$network validated=$validated",
        )
        scheduleProbe(
            reason = "network:$description",
            delayMillis = NETWORK_PROBE_DELAY_MILLIS,
            resetConnectionsBeforeProbe = shouldResetConnections,
            waitForNetwork = true,
        )
    }

    fun onDeviceSuspensionChanged(suspended: Boolean) {
        val shouldProbe = synchronized(stateLock) {
            if (stopped) return
            val wasSuspended = this.suspended
            this.suspended = suspended
            wasSuspended && !suspended
        }
        if (shouldProbe) {
            GlobalState.log("VPN health: device resumed; refreshing network and data path")
            service.requestUnderlyingNetworkRefreshForHealth("resume")
            scheduleProbe(
                reason = "resume",
                delayMillis = RESUME_PROBE_DELAY_MILLIS,
                resetConnectionsBeforeProbe = true,
                waitForNetwork = true,
            )
        }
    }

    fun stop() {
        synchronized(stateLock) {
            if (stopped) return
            stopped = true
            generation++
            jobs.clear()
        }
        scope.cancel()
    }

    private fun scheduleProbe(
        reason: String,
        delayMillis: Long,
        resetConnectionsBeforeProbe: Boolean = false,
        waitForNetwork: Boolean = false,
    ) {
        val requestGeneration = synchronized(stateLock) {
            if (stopped || suspended) return
            generation
        }

        val job = scope.launch {
            delay(delayMillis)
            val snapshot = awaitReadySnapshot(
                requestGeneration = requestGeneration,
                reason = reason,
                waitForNetwork = waitForNetwork,
            ) ?: return@launch

            probeMutex.withLock {
                if (!isSnapshotCurrent(snapshot) || !service.isTunnelRunningForHealth()) {
                    return@withLock
                }

                if (resetConnectionsBeforeProbe) {
                    service.resetConnectionsForHealth("event:$reason")
                    delay(CONNECTION_RESET_SETTLE_MILLIS)
                    if (!isSnapshotCurrent(snapshot) || !service.isTunnelRunningForHealth()) {
                        return@withLock
                    }
                }

                val result = probeDataPlane()
                if (!isSnapshotCurrent(snapshot) || !service.isTunnelRunningForHealth()) {
                    return@withLock
                }

                if (result.healthy) {
                    val recovered = synchronized(stateLock) { policy.onSuccess() }
                    if (recovered) {
                        GlobalState.log(
                            "VPN health: recovered on ${snapshot.underlyingDescription} (${result.detail})",
                        )
                    }
                    return@withLock
                }

                // A cached VALIDATED bit can lag the real Android network during Wi-Fi/cellular
                // handover. Re-check capabilities before blaming the VPN data plane.
                if (!service.isUnderlyingNetworkReadyForHealth(snapshot.underlyingNetwork)) {
                    GlobalState.log(
                        "VPN health: data probe failed but underlying network is not ready; " +
                            "deferring VPN recovery ($reason, ${result.detail})",
                    )
                    service.requestUnderlyingNetworkRefreshForHealth("probe-failed:$reason")
                    scheduleProbe(
                        reason = "underlying-retry:$reason",
                        delayMillis = FAILURE_RETRY_DELAY_MILLIS,
                        waitForNetwork = true,
                    )
                    return@withLock
                }

                val decision = synchronized(stateLock) { policy.onFailure() }
                GlobalState.log(
                    "VPN health: probe failed (${decision.consecutiveFailures}) " +
                        "reason=$reason network=${snapshot.underlyingDescription} detail=${result.detail}",
                )

                when (decision.action) {
                    VpnRecoveryAction.NONE -> {
                        scheduleProbe("retry:$reason", FAILURE_RETRY_DELAY_MILLIS)
                    }

                    VpnRecoveryAction.REBUILD_TUN -> {
                        // Do one more cheap stale-session cleanup immediately before the more
                        // expensive TUN rebuild. Both operations are bounded and event-driven.
                        service.resetConnectionsForHealth("pre-tun-rebuild:$reason")
                        GlobalState.log("VPN health: rebuilding TUN after repeated data-path failure")
                        val rebuilt = service.rebuildTunnelForHealth()
                        if (rebuilt) {
                            scheduleProbe("post-tun-rebuild", POST_RECOVERY_PROBE_DELAY_MILLIS)
                        } else {
                            GlobalState.log("VPN health: TUN rebuild failed")
                            scheduleProbe("tun-rebuild-failed", FAILURE_RETRY_DELAY_MILLIS)
                        }
                    }

                    VpnRecoveryAction.STUCK -> {
                        GlobalState.log(
                            "VPN health: data path is still unavailable after stale-session reset " +
                                "and TUN rebuild; leaving the service running for diagnosis",
                        )
                    }
                }
            }
        }
        synchronized(stateLock) {
            if (!stopped) jobs += job
        }
        job.invokeOnCompletion {
            synchronized(stateLock) { jobs -= job }
        }
    }

    private suspend fun awaitReadySnapshot(
        requestGeneration: Long,
        reason: String,
        waitForNetwork: Boolean,
    ): HealthSnapshot? {
        if (waitForNetwork) {
            service.requestUnderlyingNetworkRefreshForHealth("health-wait:$reason")
        }
        val attempts = if (waitForNetwork) NETWORK_READY_ATTEMPTS else 1
        repeat(attempts) { attempt ->
            val snapshot = synchronized(stateLock) {
                if (stopped || suspended || generation != requestGeneration) {
                    return null
                }
                if (!underlyingValidated || underlyingNetwork == null) {
                    null
                } else {
                    HealthSnapshot(
                        generation = generation,
                        underlyingNetwork = underlyingNetwork,
                        underlyingValidated = underlyingValidated,
                        underlyingDescription = underlyingDescription,
                    )
                }
            }
            if (snapshot != null && service.isUnderlyingNetworkReadyForHealth(snapshot.underlyingNetwork)) {
                return snapshot
            }
            if (attempt < attempts - 1) {
                delay(NETWORK_READY_RETRY_DELAY_MILLIS)
            }
        }
        GlobalState.log(
            "VPN health: no validated underlying network became ready during bounded wait ($reason)",
        )
        return null
    }

    private fun isSnapshotCurrent(snapshot: HealthSnapshot): Boolean = synchronized(stateLock) {
        !stopped &&
            snapshot.generation == generation &&
            snapshot.underlyingNetwork == underlyingNetwork &&
            snapshot.underlyingValidated == underlyingValidated &&
            snapshot.underlyingDescription == underlyingDescription &&
            !suspended
    }

    private fun probeDataPlane(): HealthProbeResult {
        val failures = mutableListOf<String>()
        for (url in HEALTH_CHECK_URLS) {
            val result = probeUrl(url)
            if (result.healthy) {
                return result
            }
            failures += result.detail
        }
        return HealthProbeResult(
            healthy = false,
            detail = failures.joinToString(" | "),
        )
    }

    private fun probeUrl(url: String): HealthProbeResult {
        var connection: HttpURLConnection? = null
        return try {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = HEALTH_CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = HEALTH_READ_TIMEOUT_MILLIS
            connection.setRequestProperty("Cache-Control", "no-cache")
            connection.setRequestProperty("Connection", "close")
            connection.setRequestProperty("User-Agent", "Penrix/Android")
            val code = connection.responseCode
            HealthProbeResult(
                healthy = code in 100..599,
                detail = "${URL(url).host}:http=$code",
            )
        } catch (error: Exception) {
            HealthProbeResult(
                healthy = false,
                detail = "${URL(url).host}:${error.javaClass.simpleName}:${error.message.orEmpty()}",
            )
        } finally {
            connection?.disconnect()
        }
    }

    private companion object {
        val HEALTH_CHECK_URLS = arrayOf(
            "https://www.gstatic.com/generate_204",
            "https://cp.cloudflare.com/generate_204",
        )
        const val HEALTH_CONNECT_TIMEOUT_MILLIS = 4_000
        const val HEALTH_READ_TIMEOUT_MILLIS = 4_000
        const val START_PROBE_DELAY_MILLIS = 3_000L
        const val NETWORK_PROBE_DELAY_MILLIS = 1_500L
        const val RESUME_PROBE_DELAY_MILLIS = 750L
        const val FAILURE_RETRY_DELAY_MILLIS = 5_000L
        const val POST_RECOVERY_PROBE_DELAY_MILLIS = 4_000L
        const val CONNECTION_RESET_SETTLE_MILLIS = 300L
        const val NETWORK_READY_ATTEMPTS = 8
        const val NETWORK_READY_RETRY_DELAY_MILLIS = 750L
    }
}
