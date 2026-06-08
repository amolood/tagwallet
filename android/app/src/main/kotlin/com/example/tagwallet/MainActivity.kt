package com.example.tagwallet

import android.content.Context
import android.nfc.NfcAdapter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "tagwallet/hce"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "nfcStatus" -> result.success(nfcStatus())
                "setActiveTag" -> {
                    val aid = call.argument<String>("aid")
                    val response = call.argument<String>("response") ?: ""
                    val prefs = getSharedPreferences(TagHostApduService.PREFS, Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString(TagHostApduService.KEY_AID, aid)
                        .putString(TagHostApduService.KEY_RESPONSE, response)
                        .apply()
                    result.success(true)
                }
                "clearActiveTag" -> {
                    getSharedPreferences(TagHostApduService.PREFS, Context.MODE_PRIVATE)
                        .edit().clear().apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** "absent" = no NFC hardware, "disabled" = off, "enabled" = ready. */
    private fun nfcStatus(): String {
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return "absent"
        return if (adapter.isEnabled) "enabled" else "disabled"
    }
}
