package app.lumen.lumen_iptv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.view.WindowManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.lumen/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "openRecording" -> {
                    try {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        val root = File(getDir("flutter", Context.MODE_PRIVATE), "Lumen/Recordings").canonicalFile
                        require(file.path.startsWith(root.path + File.separator) && file.isFile && file.extension == "ts")
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/mp2t")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("OPEN_FAILED", "No application could open the recording.", null)
                    }
                }
                "installUpdate" -> {
                    try {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        val root = File(filesDir, "updates").canonicalFile
                        require(file.path.startsWith(root.path + File.separator) && file.isFile && file.extension == "apk")
                        val archive = packageManager.getPackageArchiveInfo(file.path, 0)
                        require(archive?.packageName == packageName) { "Wrong package identity" }
                        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                            result.error("PERMISSION", "Allow Lumen to install updates, then return and try again.", null)
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result.success(null)
                        }
                    } catch (error: Exception) {
                        result.error("INSTALL_FAILED", "Android could not open its package installer.", null)
                    }
                }
                "isTV" -> result.success((getSystemService(Context.UI_MODE_SERVICE) as UiModeManager).currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                "frameRate" -> {
                    // The caller must provide the decoded frame rate. Never guess 24/25/30 fps.
                    val enabled = call.argument<Boolean>("enabled") == true
                    val fps = call.argument<Double>("fps")
                    if (enabled && (fps == null || fps <= 0)) {
                        result.error("UNAVAILABLE", "Frame-rate metadata is unavailable for this engine.", null)
                    } else {
                        val attributes = window.attributes
                        attributes.preferredRefreshRate = if (enabled) fps!!.toFloat() else 0f
                        window.attributes = attributes
                        result.success(null)
                    }
                }
                "recording" -> {
                    val intent = Intent(this, RecordingService::class.java)
                    try {
                        if (call.argument<Boolean>("active") == true) {
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        } else stopService(intent)
                        result.success(null)
                    } catch (error: Exception) { result.error("BACKGROUND_DENIED", "Android did not allow the recording service to start.", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
}
