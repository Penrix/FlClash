package com.follow.clash.service

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
    fun onUnderlyingNetworkChanged(validated: Boolean, description: String)

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
    val underlyingValidated: Boolean,
    val underlyingDescription: String,
    val suspended: Boolean,
)

private data class HealthProbeResult(
    val healthy: Boolean,
    val detail: String,
)

/**
 * Verifies the actual VPN data path rather than process liveness. It only probes after meaningful
 * lifecycle events (start, underlying-network change, resume) and retries after a failure; there is
 * no permanent polling loop and no wakelock.
 */
internal class VpnConnectionHealth(private val service: VpnService) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val probeMutex = Mutex()
    private val policy = VpnHealthRecoveryPolicy()
    private val stateLock = Any()

    private var generation = 0L
    private var underlyingValidated = false
    private var underlyingDescription = "none"
    private var suspended = false
    private var stopped = false
    private val jobs = mutableSetOf<Job>()

    fun start(
        validated: Boolean,
        description: String,
        suspended: Boolean,
    ) {
        synchronized(stateLock) {
            if (stopped) return
            generation++
            underlyingValidated = validated
            underlyingDescription = description
            this.suspended = suspended
            policy.onNetworkChanged()
        }
        scheduleProbe("start", START_PROBE_DELAY_MILLIS)
    }

    fun onUnderlyingNetworkChanged(validated: Boolean, description: String) {
        synchronized(stateLock) {
            if (stopped) return
            generation++
            underlyingValidated = validated
            underlyingDescription = description
            policy.onNetworkChanged()
        }
        GlobalState.log(
            "VPN health: underlying=$description validated=$validated",
        )
        scheduleProbe("network:$description", NETWORK_PROBE_DELAY_MILLIS)
    }

    fun onDeviceSuspensionChanged(suspended: Boolean) {
        val shouldProbe = synchronized(stateLock) {
            if (stopped) return
            val wasSuspended = this.suspended
            this.suspended = suspended
            wasSuspended && !suspended
        }
        if (shouldProbe) {
            GlobalState.log("VPN health: device resumed, checking data path")
            scheduleProbe("resume", RESUME_PROBE_DELAY_MILLIS)
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

    private fun scheduleProbe(reason: String, delayMillis: Long) {
        val snapshot = synchronized(stateLock) {
            if (stopped || suspended || !underlyingValidated) return
            HealthSnapshot(
                generation = generation,
                underlyingValidated = underlyingValidated,
                underlyingDescription = underlyingDescription,
                suspended = suspended,
            )
        }

        val job = scope.launch {
            delay(delayMillis)
            probeMutex.withLock {
                if (!isSnapshotCurrent(snapshot) || !service.isTunnelRunningForHealth()) {
                    return@withLock
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
                            "VPN health: data path is still unavailable after TUN rebuild; " +
                                "leaving the service running for diagnosis",
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

    private fun isSnapshotCurrent(snapshot: HealthSnapshot): Boolean = synchronized(stateLock) {
        !stopped &&
            snapshot.generation == generation &&
            snapshot.underlyingValidated == underlyingValidated &&
            snapshot.underlyingDescription == underlyingDescription &&
            !suspended
    }

    private fun probeDataPlane(): HealthProbeResult {
        var connection: HttpURLConnection? = null
        return try {
            connection = URL(HEALTH_CHECK_URL).openConnection() as HttpURLConnection
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
                detail = "http=$code",
            )
        } catch (error: Exception) {
            HealthProbeResult(
                healthy = false,
                detail = "${error.javaClass.simpleName}:${error.message.orEmpty()}",
            )
        } finally {
            connection?.disconnect()
        }
    }

    private companion object {
        const val HEALTH_CHECK_URL = "https://www.gstatic.com/generate_204"
        const val HEALTH_CONNECT_TIMEOUT_MILLIS = 4_000
        const val HEALTH_READ_TIMEOUT_MILLIS = 4_000
        const val START_PROBE_DELAY_MILLIS = 3_000L
        const val NETWORK_PROBE_DELAY_MILLIS = 2_000L
        const val RESUME_PROBE_DELAY_MILLIS = 1_000L
        const val FAILURE_RETRY_DELAY_MILLIS = 5_000L
        const val POST_RECOVERY_PROBE_DELAY_MILLIS = 4_000L
    }
}
