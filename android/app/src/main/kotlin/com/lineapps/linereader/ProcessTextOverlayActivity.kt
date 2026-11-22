package com.lineapps.linereader

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Başka bir uygulamada kelime/metin seçilip "Line'da Bak" (ACTION_PROCESS_TEXT)
 * seçildiğinde arkadaki uygulamanın üzerinde şeffaf mini kart olarak açılan
 * hafif Flutter Activity'si.
 */
class ProcessTextOverlayActivity : FlutterActivity() {
    companion object {
        private const val LOOKUP_OVERLAY_CHANNEL =
            "com.lineapps.linereader/lookup_overlay"
    }

    private var lookupChannel: MethodChannel? = null
    private var initialLookupText: String? = null

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun getDartEntrypointFunctionName(): String {
        return "processTextOverlayMain"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialLookupText = extractSelectedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val nextText = extractSelectedText(intent)
        initialLookupText = nextText
        if (!nextText.isNullOrEmpty()) {
            lookupChannel?.invokeMethod("onLookupText", nextText)
        }
    }

    private fun extractSelectedText(intent: Intent?): String? {
        if (intent == null) return null
        val raw = when (intent.action) {
            Intent.ACTION_PROCESS_TEXT -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                } else {
                    intent.getStringExtra("android.intent.extra.PROCESS_TEXT")
                }
            }
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            else -> null
        }
        val cleaned = raw?.trim()
        return if (cleaned.isNullOrEmpty()) null else cleaned
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Kullanıcı Ana Ekran tuşuna basıp veya başka uygulamaya geçerek mini kartı
        // terk ettiğinde arka planda ikinci bir Line Reader görevi kalmasın.
        dismissAndRemoveTask()
    }

    private fun dismissAndRemoveTask() {
        if (!isFinishing) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                finishAndRemoveTask()
            } else {
                finish()
            }
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOOKUP_OVERLAY_CHANNEL
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLookupText" -> {
                    result.success(initialLookupText)
                }
                "closeOverlay" -> {
                    result.success(null)
                    dismissAndRemoveTask()
                }
                "openInMainApp" -> {
                    val word = call.argument<String>("word")?.trim()
                        ?: initialLookupText?.trim()
                    val openIntent = Intent(this, MainActivity::class.java).apply {
                        action = MainActivity.ACTION_OPEN_WORD_SEARCH
                        if (!word.isNullOrEmpty()) {
                            putExtra(MainActivity.EXTRA_SEARCH_WORD, word)
                        }
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                        )
                    }
                    startActivity(openIntent)
                    result.success(null)
                    dismissAndRemoveTask()
                }
                else -> result.notImplemented()
            }
        }
        lookupChannel = channel
    }
}
