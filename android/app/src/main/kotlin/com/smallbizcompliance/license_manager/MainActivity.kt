package com.smallbizcompliance.license_manager

import android.os.Build
import android.os.Bundle
import android.system.Os
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
import android.graphics.Color
import android.view.Gravity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter

class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var shield: TextView? = null
    private var epoch = 0L
    private var active = false
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) conceal("locked")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Some ARM Android emulators advertise SVE2 without executing SVE.
        // OpenSSL 4's constructor otherwise SIGILLs before SQLCipher can open.
        // Use OpenSSL's documented portable implementation on those emulators
        // only. Do not assert unsupported acceleration bits or alter real CPUs.
        // https://docs.openssl.org/master/man3/OPENSSL_armcap/
        if (Build.SUPPORTED_ABIS.firstOrNull() == "arm64-v8a" &&
            Build.HARDWARE in setOf("ranchu", "goldfish")) {
            Os.setenv("OPENSSL_armcap", "0", true)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(screenReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.smallbizcompliance/privacy")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(status())
                }
                "cover" -> { addShield(); epoch++; result.success(status()) }
                "reveal" -> {
                    val requested = call.argument<Number>("epoch")?.toLong()
                    if (active && window.decorView.hasWindowFocus() && requested == epoch) shield?.let {
                        (it.parent as? ViewGroup)?.removeView(it); shield = null
                    }
                    result.success(status())
                }
                "status" -> result.success(status())
                else -> result.notImplemented()
            }
        }
    }
    private fun status() = mapOf("epoch" to epoch, "active" to (active && window.decorView.hasWindowFocus()), "cover" to true,
        "capture" to ((window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0), "files" to false,
        "covered" to (shield != null))
    private fun addShield() {
        if (shield != null) return
        val view = TextView(this).apply {
            text = "화면 보호 중"; gravity = Gravity.CENTER; setTextColor(Color.rgb(22,119,107))
            setBackgroundColor(Color.rgb(245,248,246)); textSize = 22f
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            isFocusable = true; isClickable = true
        }
        (window.decorView as ViewGroup).addView(view, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        view.bringToFront(); shield = view
    }
    private fun conceal(state: String) {
        active = false; epoch++; addShield()
        channel?.invokeMethod("visibility", mapOf("epoch" to epoch, "state" to state))
    }
    override fun onPause() { conceal("inactive"); super.onPause() }
    override fun onStop() { conceal("background"); super.onStop() }
    override fun onResume() {
        super.onResume(); active = true; epoch++
        channel?.invokeMethod("visibility", mapOf("epoch" to epoch, "state" to if (window.decorView.hasWindowFocus()) "foreground" else "inactive"))
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) conceal("inactive")
        else {
            active = true; epoch++
            channel?.invokeMethod("visibility", mapOf("epoch" to epoch, "state" to if (window.decorView.hasWindowFocus()) "foreground" else "inactive"))
        }
    }
    override fun onDestroy() {
        unregisterReceiver(screenReceiver); channel?.setMethodCallHandler(null)
        super.onDestroy()
    }
}
