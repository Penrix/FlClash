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

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            addCapability(NetworkCapabilities.NET_CAPABILITY_FOREGROUND)
        }
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networkInfos[network] = NetworkInfo()
            updateNetworkState()
        }

        override fun onLosing(network: Network, maxMsToLive: Int) {
            val info = networkInfos[network] ?: return
            info.losingUntilMillis = System.currentTimeMillis() + maxMsToLive
            updateNetworkState()
            if (maxMsToLive > 0) {
                mainHandler.postDelayed({
                    if (networkInfos.containsKey(network)) {
                        updateNetworkState()
                    }
                }, maxMsToLive.toLong() + 50)
            }
        }

        override fun onLost(network: Network) {
            networkInfos.remove(network)
            updateNetworkState()
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            networkInfos[network]?.dnsList = linkProperties.dnsServers
            updateNetworkState()
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            if (networkInfos.containsKey(network)) {
                updateNetworkState()
            }
        }
    }

    override fun start() {
        updateNetworkState()
        connectivity?.registerNetworkCallback(request, callback)
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
        return transportPriority + validationPenalty + entry.value.priorityPenalty
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
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
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
                "Underlying network selected: $description validated=$validated",
            )
            (service as? VpnHealthSignalSink)?.onUnderlyingNetworkChanged(
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
        mainHandler.removeCallbacksAndMessages(null)
        try {
            connectivity?.unregisterNetworkCallback(callback)
        } finally {
            networkInfos.clear()
            updateNetworkState()
        }
    }
}

private const val DNS_PORT = 53

private fun InetAddress.asSocketAddressText(port: Int): String = when (this) {
    is Inet6Address -> "[$hostAddress]:$port"
    is Inet4Address -> "$hostAddress:$port"
    else -> error("Unsupported address type: ${javaClass.name}")
}
