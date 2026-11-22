package com.lineapps.linereader

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.ActionMode
import android.view.Menu
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val SELECTION_MODE_CHANNEL =
            "com.lineapps.linereader/selection_mode"
        private const val APP_UPDATER_CHANNEL =
            "com.lineapps.linereader/app_updater"
        private const val PROCESS_TEXT_CHANNEL =
            "com.lineapps.linereader/process_text"
        const val ACTION_OPEN_WORD_SEARCH =
            "com.lineapps.linereader.ACTION_OPEN_WORD_SEARCH"
        const val EXTRA_SEARCH_WORD =
            "com.lineapps.linereader.EXTRA_SEARCH_WORD"
    }

    private var isPenModeActive: Boolean = true
    private var activeActionMode: ActionMode? = null
    private var processTextChannel: MethodChannel? = null
    private var pendingProcessText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashScreenView ->
                splashScreenView.remove()
            }
        }
        extractProcessText(intent)?.let { text ->
            pendingProcessText = text
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractProcessText(intent)?.let { text ->
            val channel = processTextChannel
            if (channel != null) {
                pendingProcessText = null
                channel.invokeMethod("onProcessText", text)
            } else {
                pendingProcessText = text
            }
        }
    }

    private fun extractProcessText(intent: Intent?): String? {
        if (intent == null) return null
        val raw = when (intent.action) {
            ACTION_OPEN_WORD_SEARCH -> intent.getStringExtra(EXTRA_SEARCH_WORD)
            Intent.ACTION_PROCESS_TEXT -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                } else {
                    intent.getStringExtra("android.intent.extra.PROCESS_TEXT")
                }
            }
            else -> null
        }
        val cleaned = raw?.trim()
        return if (cleaned.isNullOrEmpty()) null else cleaned
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SELECTION_MODE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setPenMode" -> {
                    isPenModeActive = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                "finishActionMode" -> {
                    activeActionMode?.finish()
                    activeActionMode = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> {
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "APK dosya yolu boş.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApkFile(File(filePath))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        val ptChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PROCESS_TEXT_CHANNEL
        )
        ptChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialProcessText" -> {
                    val text = pendingProcessText
                    pendingProcessText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
        processTextChannel = ptChannel
    }

    private fun installApkFile(apkFile: File) {
        if (!apkFile.exists()) {
            throw IllegalStateException("APK dosyası bulunamadı: ${apkFile.absolutePath}")
        }

        val apkUri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile
        )

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(installIntent)
    }

    override fun onActionModeStarted(mode: ActionMode?) {
        super.onActionModeStarted(mode)
        if (mode == null) return

        activeActionMode = mode
        val menu = mode.menu ?: return
        if (isPenModeActive) {
            // Kalem modu aktifken Copy / Select All / Share menüsünü temizleyip
            // gizle; ancak mode.finish() çağrısını hemen YAPMA ki Chromium
            // WebView metin seçimini silmeden JS `selectionchange` / `touchend`
            // üzerinden kelimeyi Flutter'a iletebilsin.
            menu.clear()
            return
        }

        // Kalem modu kapalıyken yalnızca Kopyala ve Tümünü Seç aksiyonlarını bırak.
        filterMenuToCopyAndSelectAll(menu)
    }

    override fun onActionModeFinished(mode: ActionMode?) {
        super.onActionModeFinished(mode)
        if (activeActionMode == mode) {
            activeActionMode = null
        }
    }

    private fun filterMenuToCopyAndSelectAll(menu: Menu) {
        val idsToRemove = mutableListOf<Int>()
        for (i in 0 until menu.size()) {
            val item = menu.getItem(i)
            if (!isAllowedSelectionAction(item.itemId, item.title?.toString())) {
                item.isVisible = false
                item.isEnabled = false
                if (item.itemId != Menu.NONE) {
                    idsToRemove.add(item.itemId)
                }
            }
        }
        for (id in idsToRemove) {
            menu.removeItem(id)
        }
    }

    private fun isAllowedSelectionAction(itemId: Int, rawTitle: String?): Boolean {
        if (itemId == android.R.id.copy || itemId == android.R.id.selectAll) {
            return true
        }
        val title = rawTitle?.trim()?.lowercase() ?: return false
        return title == "copy" ||
            title == "kopyala" ||
            title == "select all" ||
            title == "tümünü seç" ||
            title == "tumunu sec" ||
            title == "hepsini seç"
    }
}
