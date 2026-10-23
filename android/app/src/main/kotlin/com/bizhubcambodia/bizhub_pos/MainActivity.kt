package com.bizhubcambodia.bizhub_pos

import android.Manifest
import android.app.Presentation
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

// The counter app + the customer screen of dual-screen terminals (Sunmi D2, iMin…).
// Dart (lib/core/customer_display.dart) sends a picture on "bizhub/display"; we show it on the second display
// with a second Flutter engine started at displayMain (lib/main.dart), which listens on "bizhub/display_view".
class MainActivity : FlutterActivity() {
    private var presentation: CustomerPresentation? = null
    private var displayEngine: FlutterEngine? = null
    private var viewChannel: MethodChannel? = null
    private var last: String? = null
    private var permResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android 12+: "Nearby devices" (BLUETOOTH_CONNECT) for the Bluetooth receipt printer — without it the printer
        // plugin never answers. → "granted" | "denied" | "blocked" (denied for good: only the phone Settings can allow it)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bizhub/perm").setMethodCallHandler { call, result ->
            if (call.method != "bluetooth") return@setMethodCallHandler result.notImplemented()
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                return@setMethodCallHandler result.success("granted")
            }
            permResult?.success("denied")
            permResult = result
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN), PERM_BT)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bizhub/display").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "available" -> result.success(secondDisplay() != null)
                    "show" -> {
                        last = call.arguments as? String
                        showScreen()
                        send()
                        result.success(presentation?.isShowing == true)
                    }
                    "hide" -> {
                        hideScreen()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("display", e.message, null)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERM_BT) return
        val i = permissions.indexOf(Manifest.permission.BLUETOOTH_CONNECT)
        val ok = i >= 0 && grantResults.getOrNull(i) == PackageManager.PERMISSION_GRANTED
        // asked before and now refused without a dialog → only the Settings can turn it on
        val blocked = !ok && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !shouldShowRequestPermissionRationale(Manifest.permission.BLUETOOTH_CONNECT)
        permResult?.success(if (ok) "granted" else if (blocked) "blocked" else "denied")
        permResult = null
    }

    // the screen facing the customer: a "presentation" display (built in, or HDMI)
    private fun secondDisplay(): Display? {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull { it.displayId != Display.DEFAULT_DISPLAY }
    }

    private fun showScreen() {
        if (presentation?.isShowing == true) return
        val display = secondDisplay() ?: return
        val engine = displayEngine ?: FlutterEngine(this).also { e ->
            val channel = MethodChannel(e.dartExecutor.binaryMessenger, "bizhub/display_view")
            channel.setMethodCallHandler { call, result ->
                if (call.method == "hello") send() // the screen just started: give it the picture now
                result.success(null)
            }
            viewChannel = channel
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundle, "displayMain"))
            displayEngine = e
        }
        presentation = CustomerPresentation(this, display, engine).also {
            it.setOnDismissListener { _ -> presentation = null }
            it.show()
        }
    }

    private fun send() {
        val pic = last ?: return
        viewChannel?.invokeMethod("pic", pic)
    }

    private fun hideScreen() {
        presentation?.dismiss()
        presentation = null
    }

    override fun onDestroy() {
        hideScreen()
        displayEngine?.destroy()
        displayEngine = null
        viewChannel = null
        super.onDestroy()
    }
}

private const val PERM_BT = 7301

// a window on the second display that holds the customer-screen engine
class CustomerPresentation(context: Context, display: Display, private val engine: FlutterEngine) : Presentation(context, display) {
    private var view: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val v = FlutterView(context)
        setContentView(v)
        v.attachToFlutterEngine(engine)
        engine.lifecycleChannel.appIsResumed() // draw frames even when the counter app is paused
        view = v
    }

    override fun onStop() {
        view?.detachFromFlutterEngine()
        view = null
        super.onStop()
    }
}
