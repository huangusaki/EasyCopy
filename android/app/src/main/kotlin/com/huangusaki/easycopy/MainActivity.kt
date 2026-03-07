package com.huangusaki.easycopy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumePagingEnabled = false
    private var batteryReceiver: BroadcastReceiver? = null
    private var batteryEventSink: EventChannel.EventSink? = null
    private var volumeKeyEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }

                "setVolumePagingEnabled" -> {
                    volumePagingEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_EVENT_CHANNEL_NAME,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    batteryEventSink = events
                    val receiver =
                        object : BroadcastReceiver() {
                            override fun onReceive(context: Context?, intent: Intent?) {
                                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                                if (level <= 0 || scale <= 0) {
                                    batteryEventSink?.success(0)
                                    return
                                }
                                val percentage = (level * 100) / scale
                                batteryEventSink?.success(percentage.coerceIn(0, 100))
                            }
                        }
                    batteryReceiver = receiver
                    registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                }

                override fun onCancel(arguments: Any?) {
                    batteryEventSink = null
                    batteryReceiver?.let { receiver ->
                        runCatching { unregisterReceiver(receiver) }
                    }
                    batteryReceiver = null
                }
            },
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOLUME_KEY_EVENT_CHANNEL_NAME,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeKeyEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    volumeKeyEventSink = null
                }
            },
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (
            volumePagingEnabled &&
                event.action == KeyEvent.ACTION_DOWN &&
                (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                    event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            val action = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "previous" else "next"
            volumeKeyEventSink?.success(action)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        batteryReceiver?.let { receiver ->
            runCatching { unregisterReceiver(receiver) }
        }
        batteryReceiver = null
        batteryEventSink = null
        volumeKeyEventSink = null
        super.onDestroy()
    }

    companion object {
        private const val METHOD_CHANNEL_NAME = "easy_copy/reader_platform/methods"
        private const val BATTERY_EVENT_CHANNEL_NAME = "easy_copy/reader_platform/battery"
        private const val VOLUME_KEY_EVENT_CHANNEL_NAME = "easy_copy/reader_platform/volume_keys"
    }
}
