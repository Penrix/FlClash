package com.follow.clash.service.modules

import android.app.Service
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

internal interface ServiceModule {
    fun start()

    fun stop()
}

internal class ServiceModules(private val service: Service) {
    private var scope: CoroutineScope? = null
    private var modules = emptyList<ServiceModule>()

    @Volatile
    private var networkObserveModule: NetworkObserveModule? = null

    @Synchronized
    fun start() {
        if (scope != null) return

        val nextScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val nextNetworkObserveModule = NetworkObserveModule(service)
        val nextModules = listOf(
            NotificationModule(service, nextScope),
            nextNetworkObserveModule,
            SuspendModule(service, nextScope),
        )
        val startedModules = mutableListOf<ServiceModule>()

        try {
            nextModules.forEach { module ->
                module.start()
                startedModules.add(module)
            }
            scope = nextScope
            modules = nextModules
            networkObserveModule = nextNetworkObserveModule
        } catch (error: Throwable) {
            networkObserveModule = null
            nextScope.cancel()
            startedModules.asReversed().forEach { module ->
                runCatching { module.stop() }
            }
            throw error
        }
    }

    fun refreshUnderlyingNetwork(reason: String) {
        networkObserveModule?.refreshAfterSystemTransition(reason)
    }

    @Synchronized
    fun stop() {
        val currentScope = scope ?: return
        val currentModules = modules
        scope = null
        modules = emptyList()
        networkObserveModule = null

        currentScope.cancel()
        currentModules.asReversed().forEach { module ->
            runCatching { module.stop() }
        }
    }
}
