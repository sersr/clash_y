package io.aote.vpnService

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class VpnServicePlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL = "vpn_service"
        private const val REQUEST_VPN = 0x5650
    }

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfigDir: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "close" -> close(result)
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val configDir = call.argument<String>("configDir")?.trim().orEmpty()
        if (configDir.isEmpty()) {
            result.success(false)
            return
        }

        val appContext = context
        if (appContext == null) {
            result.success(false)
            return
        }

        val prepareIntent = VpnService.prepare(appContext)
        if (prepareIntent == null) {
            startVpnService(ClashVpnService.ACTION_START, configDir, result)
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            result.success(false)
            return
        }

        if (pendingResult != null) {
            result.success(false)
            return
        }

        pendingResult = result
        pendingConfigDir = configDir
        currentActivity.startActivityForResult(prepareIntent, REQUEST_VPN)
    }

    private fun close(result: MethodChannel.Result) {
        val appContext = context
        if (appContext == null) {
            result.success(false)
            return
        }

        startVpnService(ClashVpnService.ACTION_STOP, null, result, closeServiceAfter = true)
    }

    private fun startVpnService(
        action: String,
        configDir: String?,
        result: MethodChannel.Result,
        closeServiceAfter: Boolean = false,
    ) {
        val appContext = context
        if (appContext == null) {
            result.success(false)
            return
        }

        val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                val success = resultData?.getBoolean("success")
                    ?: (resultCode == Activity.RESULT_OK)
                result.success(success)
                if (closeServiceAfter) {
                    stopVpnService(appContext)
                }
            }
        }

        val intent = Intent(appContext, ClashVpnService::class.java).apply {
            this.action = action
            if (configDir != null) {
                putExtra(ClashVpnService.EXTRA_CONFIG_DIR, configDir)
            }
            putExtra(ClashVpnService.EXTRA_RESULT_RECEIVER, receiver)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
        } catch (t: Throwable) {
            result.success(false)
            if (closeServiceAfter) {
                stopVpnService(appContext)
            }
        }
    }

    private fun stopVpnService(context: Context) {
        context.stopService(Intent(context, ClashVpnService::class.java))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_VPN) {
            return false
        }

        val result = pendingResult ?: return true
        val configDir = pendingConfigDir
        pendingResult = null
        pendingConfigDir = null

        if (resultCode == Activity.RESULT_OK && configDir != null && configDir.isNotEmpty()) {
            startVpnService(ClashVpnService.ACTION_START, configDir, result)
        } else {
            result.success(false)
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }
}
