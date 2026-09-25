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
}

internal data class VpnHealthDecision(
    val action: VpnRecoveryAction,
    val consecutiveFailures: Int,
)

/**
 * Pure recovery policy. A single slow request never rebuilds the tunnel. Repeated data-plane
 * failures request a local TUN rebuild, and repeated rebuilds are followed by an increasingly long
 * probe delay. The delay is capped instead of ending in a permanent STUCK state, so an unattended
 * phone can eventually recover after Android's real network becomes usable again.
 */
internal class VpnHealthRecoveryPolicy(
    private val failuresBeforeRecovery: Int = 2,
    private val recoveryProbeDelaysMillis: List<Long> = DEFAULT_RECOVERY_PROBE_DELAYS_MILLIS,
) {
    private var consecutiveFailures = 0
    private var recoveryAttempts = 0

    init {
        require(failuresBeforeRecovery > 0)
        require(recoveryProbeDelaysMillis.isNotEmpty())
        require(recoveryProbeDelaysMillis.all { it > 0 })
    }

    fun onSuccess(): Boolean {
        val hadProblem = consecutiveFailures > 0 || recoveryAttempts > 0
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
        return VpnHealthDecision(VpnRecoveryAction.REBUILD_TUN, count)
    }

    /**
     * Records an actual local recovery attempt and returns when the next probe/recovery may run.
     * The first rebuild is checked quickly; persistent failure backs off to 30s, 2m, then 5m and
     * stays at 5m until success or a real underlying-network change resets the policy.
     */
    fun onRecoveryAttempted(): Long {
        val index = recoveryAttempts.coerceAtMost(recoveryProbeDelaysMillis.lastIndex)
        val delayMillis = recoveryProbeDelaysMillis[index]
        recoveryAttempts++
        return delayMillis
    }

    private fun reset() {
        consecutiveFailures = 0
        recoveryAttempts = 0
    }

    private companion object {
        val DEFAULT_RECOVERY_PROBE_DELAYS_MILLIS = listOf(
            5_000L,
            15_000L,
            30_000L,
            60_000L,
        )
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
 * Verifies the actual VPN data path rather than process liveness. This build intentionally runs an
 * aggressive watchdog while the VPN is active: healthy tunnels are re-probed periodically, deep
 * idle does not pause the watchdog, and missing network callbacks cannot leave recovery permanently
 * dormant. Repeated failures rebuild the local TUN/Core data path with a short capped backoff.
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
        synchronized(stateLock) {
            if (stopped) return
            generation++
            this.suspended = suspended
        }

        val reason = if (suspended) "idle-enter" else "resume"
        GlobalState.log("VPN health: device state changed: $reason")
        service.requestUnderlyingNetworkRefreshForHealth(reason)
        scheduleProbe(
            reason = reason,
            delayMillis = if (suspended) IDLE_PROBE_DELAY_MILLIS else RESUME_PROBE_DELAY_MILLIS,
            resetConnectionsBeforeProbe = !suspended,
            waitForNetwork = true,
        )
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
            if (stopped) return
            generation
        }

        val job = scope.launch {
            delay(delayMillis)
            val snapshot = awaitReadySnapshot(
                requestGeneration = requestGeneration,
                reason = reason,
                waitForNetwork = waitForNetwork,
            )
            if (snapshot == null) {
                scheduleProbe(
                    reason = "network-watch:$reason",
                    delayMillis = NETWORK_MISSING_RETRY_DELAY_MILLIS,
                    waitForNetwork = true,
                )
                return@launch
            }

            probeMutex.withLock {
                if (!isSnapshotCurrent(snapshot)) {
                    return@withLock
                }

                // A failed rebuild can leave the Android service alive while Core no longer owns a
                // TUN. That state used to make the next health probe return forever. Treat it as a
                // recoverable data-path failure and keep attempting a local start with capped delay.
                if (!service.isTunnelRunningForHealth()) {
                    GlobalState.log("VPN health: TUN is missing; attempting local data-path recovery")
                    val rebuilt = service.rebuildTunnelForHealth()
                    val nextDelay = synchronized(stateLock) { policy.onRecoveryAttempted() }
                    if (rebuilt) {
                        GlobalState.log("VPN health: missing TUN recovered")
                        scheduleProbe(
                            reason = "post-missing-tun-recovery",
                            delayMillis = nextDelay,
                            waitForNetwork = true,
                        )
                    } else {
                        GlobalState.log(
                            "VPN health: missing TUN recovery failed; retrying in ${nextDelay}ms",
                        )
                        scheduleProbe(
                            reason = "missing-tun-retry",
                            delayMillis = nextDelay,
                            waitForNetwork = true,
                        )
                    }
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
                    scheduleProbe(
                        reason = "watchdog",
                        delayMillis = HEALTHY_WATCHDOG_INTERVAL_MILLIS,
                        waitForNetwork = true,
                    )
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
                        // Do one more cheap stale-session cleanup immediately before recreating the
                        // complete local TUN/Core data path. If the fault persists, later rebuilds
                        // are spaced out by the recovery policy instead of ending in STUCK.
                        service.resetConnectionsForHealth("pre-tun-rebuild:$reason")
                        GlobalState.log("VPN health: rebuilding TUN after repeated data-path failure")
                        val rebuilt = service.rebuildTunnelForHealth()
                        val nextDelay = synchronized(stateLock) { policy.onRecoveryAttempted() }
                        if (rebuilt) {
                            scheduleProbe(
                                reason = "post-tun-rebuild",
                                delayMillis = nextDelay,
                                waitForNetwork = true,
                            )
                        } else {
                            GlobalState.log(
                                "VPN health: TUN rebuild failed; recovery will retry in ${nextDelay}ms",
                            )
                            scheduleProbe(
                                reason = "tun-rebuild-failed",
                                delayMillis = nextDelay,
                                waitForNetwork = true,
                            )
                        }
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
                if (stopped || generation != requestGeneration) {
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
            snapshot.underlyingDescription == underlyingDescription
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
            connection.setRequestProperty("User-Agent", "FlClash/Android-Watchdog")
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
        const val RESUME_PROBE_DELAY_MILLIS = 500L
        const val IDLE_PROBE_DELAY_MILLIS = 2_000L
        const val HEALTHY_WATCHDOG_INTERVAL_MILLIS = 45_000L
        const val NETWORK_MISSING_RETRY_DELAY_MILLIS = 10_000L
        const val FAILURE_RETRY_DELAY_MILLIS = 5_000L
        const val CONNECTION_RESET_SETTLE_MILLIS = 300L
        const val NETWORK_READY_ATTEMPTS = 8
        const val NETWORK_READY_RETRY_DELAY_MILLIS = 750L
    }
}
