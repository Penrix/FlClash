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
    fun `a rebuilt tunnel that still fails is reported stuck instead of churning`() {
        val policy = VpnHealthRecoveryPolicy(failuresBeforeRecovery = 2)

        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.REBUILD_TUN, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.STUCK, policy.onFailure().action)

        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
    }

    @Test
    fun `success clears recovery state`() {
        val policy = VpnHealthRecoveryPolicy(failuresBeforeRecovery = 2)

        policy.onFailure()
        assertEquals(VpnRecoveryAction.REBUILD_TUN, policy.onFailure().action)
        assertTrue(policy.onSuccess())

        assertEquals(VpnRecoveryAction.NONE, policy.onFailure().action)
        assertEquals(VpnRecoveryAction.REBUILD_TUN, policy.onFailure().action)
    }

    @Test
    fun `network change clears failures from the previous network`() {
        val policy = VpnHealthRecoveryPolicy(failuresBeforeRecovery = 3)

        assertEquals(1, policy.onFailure().consecutiveFailures)
        assertEquals(2, policy.onFailure().consecutiveFailures)
        policy.onNetworkChanged()

        val decision = policy.onFailure()
        assertEquals(VpnRecoveryAction.NONE, decision.action)
        assertEquals(1, decision.consecutiveFailures)
        assertFalse(policy.onSuccess().not())
    }
}
