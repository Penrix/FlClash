package com.follow.clash.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.SystemClock
import com.follow.clash.common.BroadcastAction
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.action
import com.follow.clash.common.sendBroadcast

interface ManagedService {
    fun start()

    fun stop()
}

internal fun Service.notifyVpnStartRequested() {
    GlobalState.log("VPN start requested")
    BroadcastAction.VPN_START_REQUESTED.sendBroadcast()
}

internal fun Service.notifyVpnRevoked() {
    GlobalState.log("VPN permission revoked")
    BroadcastAction.VPN_REVOKED.sendBroadcast()
}

/**
 * Some Android vendors kill the app process when its task is removed even while
 * a foreground VPN service is running. Keep the recovery outside that process:
 * AlarmManager owns the PendingIntent and can relaunch the explicit receiver
 * after the task-removal kill has completed.
 */
internal fun Service.scheduleVpnTaskRemovalRecovery() {
    val alarmManager = getSystemService(AlarmManager::class.java) ?: return
    alarmManager.setAndAllowWhileIdle(
        AlarmManager.ELAPSED_REALTIME_WAKEUP,
        SystemClock.elapsedRealtime() + TASK_REMOVAL_RECOVERY_DELAY_MILLIS,
        vpnTaskRemovalRecoveryIntent(),
    )
    GlobalState.log("Scheduled VPN recovery after task removal")
}

internal fun Service.cancelVpnTaskRemovalRecovery() {
    getSystemService(AlarmManager::class.java)?.cancel(vpnTaskRemovalRecoveryIntent())
}

private fun Service.vpnTaskRemovalRecoveryIntent(): PendingIntent {
    val intent = Intent(BroadcastAction.VPN_START_REQUESTED.action).apply {
        component = Components.serviceBroadcastReceiver
    }
    return PendingIntent.getBroadcast(
        this,
        TASK_REMOVAL_RECOVERY_REQUEST_CODE,
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

private const val TASK_REMOVAL_RECOVERY_REQUEST_CODE = 0x504E5258
private const val TASK_REMOVAL_RECOVERY_DELAY_MILLIS = 1_500L
