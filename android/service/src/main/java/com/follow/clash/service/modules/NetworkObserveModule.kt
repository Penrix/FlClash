package com.follow.clash.service.modules

import android.app.Service
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkCapabilities.TRANSPORT_SATELLITE
import android.net.NetworkCapabilities.TRANSPORT_USB
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.getSystemService
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import com.follow.clash.service.VpnHealthSignalSink
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

private data class NetworkInfo(
    @Volatile var losingUntilMillis: Long = 0,
    @Volatile var dnsList: List<InetAddress> = emptyList(),
) {
    val priorityPenalty: Int
        get() = if (losingUntilMillis > System.currentTimeMillis()) 10 else 0
}

internal class NetworkObserveModule(private val service: Service) : ServiceModule {

    private val networkInfos = ConcurrentHashMap<Network, NetworkInfo>()
    private val connectivity by lazy {
        service.getSystemService<ConnectivityManager>()
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentDnsList = listOf<String>()
    private var currentNetwork: Network? = null
    private var currentNetworkValidated = false
    private var currentNetworkDescription = "none"

    @Volatile
    private var started = false

    // Do not require FOREGROUND/NOT_RESTRICTED here. A foreground VPN must keep observing the real
    // physical INTERNET network while the phone is idle or Data Saver changes capabilities. The
    // selected network is still filtered to NOT_VPN and re-ranked by validation + transport.
    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }.build()

    private val updateRunnable = Runnable {
        if (!started) return@Runnable
        reconcileNetworksFromSystem()
        updateNetworkState()
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            if (!started) return
            networkInfos.putIfAbsent(network, NetworkInfo())
            connectivity?.getLinkProperties(network)?.let { properties ->
                networkInfos[network]?.dnsList = properties.dnsServers
            }
            scheduleNetworkStateUpdate()
        }

        override fun onLosing(network: Network, maxMsToLive: Int) {
            if (!started) return
            val info = networkInfos[network] ?: return
            info.losingUntilMillis = System.currentTimeMillis() + maxMsToLive
            scheduleNetworkStateUpdate()
            if (maxMsToLive > 0) {
                mainHandler.postDelayed({
                    if (started && networkInfos.containsKey(network)) {
                        scheduleNetworkStateUpdate(0)
                    }
                }, maxMsToLive.toLong() + 50)
            }
        }

        override fun onLost(network: Network) {
            if (!started) return
            networkInfos.remove(network)
            scheduleNetworkStateUpdate()
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            if (!started) return
            networkInfos[network]?.dnsList = linkProperties.dnsServers
            scheduleNetworkStateUpdate()
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            if (!started) return
            if (isEligibleNetwork(networkCapabilities)) {
                networkInfos.putIfAbsent(network, NetworkInfo())
            }
            scheduleNetworkStateUpdate()
        }
    }

    override fun start() {
        if (started) return
        started = true
        connectivity?.registerNetworkCallback(request, callback)
        refreshAfterSystemTransition("start")
    }

    /**
     * Network callbacks are hints, not a perfectly ordered snapshot. Resume and failed health probes
     * ask for a bounded inventory refresh immediately and again after Android has had time to settle.
     * This is event-driven; there is no periodic background scan.
     */
    fun refreshAfterSystemTransition(reason: String) {
        if (!started) return
        GlobalState.log("Underlying network refresh requested: $reason")
        scheduleNetworkStateUpdate(0)
        mainHandler.postDelayed({
            if (started) scheduleNetworkStateUpdate(0)
        }, SETTLE_REFRESH_DELAY_MILLIS)
        mainHandler.postDelayed({
            if (started) scheduleNetworkStateUpdate(0)
        }, FINAL_REFRESH_DELAY_MILLIS)
    }

    private fun scheduleNetworkStateUpdate(delayMillis: Long = NETWORK_EVENT_DEBOUNCE_MILLIS) {
        if (!started) return
        mainHandler.removeCallbacks(updateRunnable)
        mainHandler.postDelayed(updateRunnable, delayMillis)
    }

    private fun isEligibleNetwork(capabilities: NetworkCapabilities?): Boolean {
        capabilities ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }

    private fun reconcileNetworksFromSystem() {
        val manager = connectivity ?: return
        val liveNetworks = runCatching { manager.allNetworks.toList() }
            .onFailure { error ->
                GlobalState.log("Unable to refresh underlying networks: $error")
            }
            .getOrDefault(emptyList())

        val eligibleNetworks = mutableSetOf<Network>()
        liveNetworks.forEach { network ->
            val capabilities = manager.getNetworkCapabilities(network)
            if (!isEligibleNetwork(capabilities)) return@forEach
            eligibleNetworks += network
            val info = networkInfos[network] ?: NetworkInfo().also {
                networkInfos[network] = it
            }
            manager.getLinkProperties(network)?.let { properties ->
                info.dnsList = properties.dnsServers
            }
        }

        networkInfos.keys.toList()
            .filter { it !in eligibleNetworks }
            .forEach { networkInfos.remove(it) }
    }

    private fun networkPriority(entry: Map.Entry<Network, NetworkInfo>): Int {
        val capabilities = connectivity?.getNetworkCapabilities(entry.key)
        val validationPenalty = if (
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        ) {
            0
        } else {
            20
        }
        val suspendedPenalty = if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED) == false
        ) {
            30
        } else {
            0
        }
        val transportPriority = when {
            capabilities == null -> 100
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> 90
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                capabilities.hasTransport(TRANSPORT_USB) -> 2

            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> 3
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 4
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
                capabilities.hasTransport(TRANSPORT_SATELLITE) -> 5

            else -> 20
        }
        return transportPriority + validationPenalty + suspendedPenalty + entry.value.priorityPenalty
    }

    private fun describeNetwork(capabilities: NetworkCapabilities?): String = when {
        capabilities == null -> "unknown"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            capabilities.hasTransport(TRANSPORT_USB) -> "usb"

        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
            capabilities.hasTransport(TRANSPORT_SATELLITE) -> "satellite"

        else -> "other"
    }

    @Synchronized
    private fun updateNetworkState() {
        val selected = networkInfos.entries.minByOrNull(::networkPriority)
        val network = selected?.key
        val capabilities = network?.let { connectivity?.getNetworkCapabilities(it) }
        val validated =
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true &&
                (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
                        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED)
                    )
        val description = if (network == null) "none" else describeNetwork(capabilities)

        if (
            network != currentNetwork ||
            validated != currentNetworkValidated ||
            description != currentNetworkDescription
        ) {
            currentNetwork = network
            currentNetworkValidated = validated
            currentNetworkDescription = description
            GlobalState.log(
                "Underlying network selected: $description network=$network validated=$validated",
            )
            (service as? VpnHealthSignalSink)?.onUnderlyingNetworkChanged(
                network = network,
                validated = validated,
                description = description,
            )
        }

        val dnsList = selected
            ?.value
            ?.dnsList
            .orEmpty()
            .map { address -> address.asSocketAddressText(DNS_PORT) }
            .distinct()
        if (dnsList == currentDnsList) {
            return
        }
        currentDnsList = dnsList
        Core.updateDNS(dnsList.joinToString(","))
    }

    override fun stop() {
        if (!started) return
        started = false
        mainHandler.removeCallbacksAndMessages(null)
        try {
            connectivity?.unregisterNetworkCallback(callback)
        } finally {
            networkInfos.clear()
            updateNetworkState()
        }
    }

    private companion object {
        const val NETWORK_EVENT_DEBOUNCE_MILLIS = 250L
        const val SETTLE_REFRESH_DELAY_MILLIS = 1_000L
        const val FINAL_REFRESH_DELAY_MILLIS = 3_000L
    }
}

private const val DNS_PORT = 53

private fun InetAddress.asSocketAddressText(port: Int): String = when (this) {
    is Inet6Address -> "[$hostAddress]:$port"
    is Inet4Address -> "$hostAddress:$port"
    else -> error("Unsupported address type: ${javaClass.name}")
}
