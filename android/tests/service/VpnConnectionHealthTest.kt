package com.follow.clash.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnConnectionHealthTest {

    @Test
    fun `three consecutive failures request one local tun rebuild`() {
        val policy = VpnHealthRecoveryPolicy(failuresBeforeRecovery = 3)

        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        val decision = policy.onFailure()

        assertEquals(VpnRecoveryAction.REBUILD_TUN, decision.action)
        assertEquals(3, decision.consecutiveFailures)
    }

    @Test
    fun `persistent failure keeps rebuilding with capped recovery backoff`() {
        val policy = VpnHealthRecoveryPolicy(
            failuresBeforeRecovery = 2,
            recoveryProbeDelaysMillis = listOf(4_000L, 30_000L, 120_000L, 300_000L),
        )

        assertRecovery(policy, expectedDelayMillis = 4_000L)
        assertRecovery(policy, expectedDelayMillis = 30_000L)
        assertRecovery(policy, expectedDelayMillis = 120_000L)
        assertRecovery(policy, expectedDelayMillis = 300_000L)
        assertRecovery(policy, expectedDelayMillis = 300_000L)
    }

    @Test
    fun `success clears failures and recovery backoff`() {
        val policy = VpnHealthRecoveryPolicy(
            failuresBeforeRecovery = 2,
            recoveryProbeDelaysMillis = listOf(4_000L, 30_000L),
        )

        assertRecovery(policy, expectedDelayMillis = 4_000L)
        assertTrue(policy.onSuccess())

        assertRecovery(policy, expectedDelayMillis = 4_000L)
    }

    @Test
    fun `network change clears failures and recovery backoff from previous network`() {
        val policy = VpnHealthRecoveryPolicy(
            failuresBeforeRecovery = 3,
            recoveryProbeDelaysMillis = listOf(4_000L, 30_000L),
        )

        assertEquals(1, policy.onFailure().consecutiveFailures)
        assertEquals(2, policy.onFailure().consecutiveFailures)
        assertEquals(VpnRecoveryAction.REBUILD_TUN, policy.onFailure().action)
        assertEquals(4_000L, policy.onRecoveryAttempted())

        assertEquals(1, policy.onFailure().consecutiveFailures)
        policy.onNetworkChanged()

        val decision = policy.onFailure()
        assertEquals(VpnRecoveryAction.NONE, decision.action)
        assertEquals(1, decision.consecutiveFailures)
        assertTrue(policy.onSuccess())
        assertFalse(policy.onSuccess())

        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.REBUILD_TUN, policy.onFailure().action)
        assertEquals(4_000L, policy.onRecoveryAttempted())
    }

    private fun assertRecovery(
        policy: VpnHealthRecoveryPolicy,
        expectedDelayMillis: Long,
    ) {
        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.REBUILD_TUN, policy.onFailure().action)
        assertEquals(expectedDelayMillis, policy.onRecoveryAttempted())
    }
}
