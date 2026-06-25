package com.vucko.cruiserconnect

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "cruise/instagram_story"
    private val instagramPkg = "com.instagram.android"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstagramAvailable" -> result.success(isInstagramInstalled())
                    "shareStorySticker" -> {
                        val path = call.argument<String>("stickerPath")
                        val appId = call.argument<String>("appId") ?: ""
                        result.success(shareSticker(path, appId))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isInstagramInstalled(): Boolean = try {
        packageManager.getPackageInfo(instagramPkg, 0)
        true
    } catch (e: Exception) {
        false
    }

    // Übergibt den transparenten Sticker an Instagram Stories. Fail-safe: false,
    // wenn Instagram fehlt, der Intent nicht aufgelöst wird oder etwas wirft.
    private fun shareSticker(path: String?, appId: String): Boolean {
        if (path.isNullOrEmpty() || !isInstagramInstalled()) return false
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
                setPackage(instagramPkg)
                type = "image/png"
                putExtra("interactive_asset_uri", uri)
                if (appId.isNotEmpty()) putExtra("source_application", appId)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            grantUriPermission(
                instagramPkg,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }
}
