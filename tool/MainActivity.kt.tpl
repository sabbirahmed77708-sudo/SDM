package __PACKAGE__

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import java.security.MessageDigest
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * SDM's activity.
 *
 * The Flutter engine (and with it the Dart download engine) is created once,
 * cached, and NOT destroyed when this activity closes. Together with
 * [DownloadService] (a foreground service) this keeps downloads running when the
 * app is in the background or has been swiped away.
 */
class SdmFileProvider : androidx.core.content.FileProvider()

/** Opens [path] with another app. Returns "ok", "noApp", "needInstallPermission", "missing" or "error". */
fun openFileNative(ctx: Context, path: String?, mime: String?): String {
    try {
        if (path == null) return "missing"
        val f = java.io.File(path)
        if (!f.exists()) return "missing"
        val isApk = mime == "application/vnd.android.package-archive"
        if (isApk && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !ctx.packageManager.canRequestPackageInstalls()) {
            val s = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                android.net.Uri.parse("package:" + ctx.packageName))
            s.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(s)
            return "needInstallPermission"
        }
        val uri = androidx.core.content.FileProvider.getUriForFile(
            ctx, ctx.packageName + ".sdmfiles", f)
        val i = Intent(Intent.ACTION_VIEW)
        i.setDataAndType(uri, mime ?: "*/*")
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
        return "ok"
    } catch (e: android.content.ActivityNotFoundException) {
        return "noApp"
    } catch (e: Exception) {
        return "error"
    }
}

class MainActivity : FlutterActivity() {

    companion object {
        const val ENGINE_ID = "drom_engine"
        const val EXTRA_OPEN = "drom_open"

        private var shareChannel: MethodChannel? = null
        private var notifyChannel: MethodChannel? = null

        @Volatile
        private var pending: String? = null

        @Volatile
        private var pendingOpen: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val existed = FlutterEngineCache.getInstance().contains(ENGINE_ID)
        if (!existed) createEngine()
        super.onCreate(savedInstanceState)

        // A link shared into the app, or a tapped "download finished" notification,
        // while the Dart side is already running (engine survived) is pushed right
        // away; on a cold start Dart asks for it.
        if (savedInstanceState == null) {
            val text = sharedText(intent)
            if (text != null) {
                if (existed) shareChannel?.invokeMethod("onShared", text) else pending = text
            }
            val open = openKey(intent)
            if (open != null) {
                if (existed) shareChannel?.invokeMethod("onOpen", open) else pendingOpen = open
            }
        }
    }

    override fun getCachedEngineId(): String = ENGINE_ID

    // Keep the engine alive after the activity is gone.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    // Plugins and channels are registered once in createEngine().
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    private fun createEngine() {
        val ctx = applicationContext
        val engine = FlutterEngine(ctx)
        GeneratedPluginRegistrant.registerWith(engine)
        setupChannels(ctx, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    private fun setupChannels(ctx: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        // Links shared from other apps ("Share" -> SDM) and notification taps.
        val share = MethodChannel(messenger, "drom/share")
        share.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    result.success(pending)
                    pending = null
                }
                "getInitialOpen" -> {
                    result.success(pendingOpen)
                    pendingOpen = null
                }
                else -> result.notImplemented()
            }
        }
        shareChannel = share

        // Wi-Fi only: is the active network Wi-Fi / Ethernet?
        MethodChannel(messenger, "drom/net").setMethodCallHandler { call, result ->
            if (call.method == "isWifi") result.success(onUnmeteredLink(ctx))
            else result.notImplemented()
        }

        // "Share app": path of the installed APK so Dart can share the file itself.
        MethodChannel(messenger, "drom/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "apkPath" -> result.success(ctx.packageCodePath)
                "openFile" -> result.success(
                    openFileNative(ctx, call.argument<String>("path"), call.argument<String>("mime")))
                // is this APK signed like the installed app? ("ok", "signature", "package", "invalid")
                "apkCompat" -> result.success(apkCompat(ctx, call.argument<String>("path")))
                else -> result.notImplemented()
            }
        }

        // Download notifications + foreground service.
        val notify = MethodChannel(messenger, "drom/notify")
        notify.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    val bundle = DownloadService.bundleOf(map)
                    val svc = DownloadService.instance
                    if (svc != null) {
                        svc.show(bundle)
                        result.success(true)
                    } else {
                        try {
                            val i = Intent(ctx, DownloadService::class.java)
                                .setAction(DownloadService.ACTION_UPDATE)
                                .putExtras(bundle)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ctx.startForegroundService(i)
                            } else {
                                ctx.startService(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "stop" -> {
                    DownloadService.stopNow()
                    result.success(true)
                }
                "done" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    showDone(ctx, map)
                    result.success(true)
                }
                "enabled" -> {
                    result.success(NotificationManagerCompat.from(ctx).areNotificationsEnabled())
                }
                "openSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        ctx.startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        notifyChannel = notify
        DownloadService.onAction = { action -> notifyChannel?.invokeMethod("onAction", action) }
    }

    /** "Download complete / failed" (and test) notifications, built from the user's settings. */
    private fun showDone(ctx: Context, m: Map<String, Any?>) {
        try {
            val id = (m["id"] as? Number)?.toInt() ?: return
            val sound = m["sound"] as? Boolean ?: true
            val vibrate = m["vibrate"] as? Boolean ?: true
            val popup = m["popup"] as? Boolean ?: true
            val failed = m["failed"] == true
            val visibility =
                (m["visibility"] as? Number)?.toInt() ?: NotificationCompat.VISIBILITY_PUBLIC
            val channel = DownloadService.doneChannelId(ctx, sound, vibrate, popup)

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                // tapping a finished download opens the file
                (m["openKey"] as? String)?.let { putExtra(EXTRA_OPEN, it) }
            }

            var defaults = 0
            if (sound) defaults = defaults or Notification.DEFAULT_SOUND
            if (vibrate) defaults = defaults or Notification.DEFAULT_VIBRATE

            val title = m["title"] as? String ?: "SDM"
            val text = m["text"] as? String ?: ""
            val builder = NotificationCompat.Builder(ctx, channel)
                .setSmallIcon(
                    if (failed) android.R.drawable.stat_notify_error
                    else android.R.drawable.stat_sys_download_done
                )
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setPriority(
                    if (popup) NotificationCompat.PRIORITY_HIGH
                    else NotificationCompat.PRIORITY_DEFAULT
                )
                .setDefaults(defaults)
                .setVisibility(visibility)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
            if (open != null) {
                builder.setContentIntent(PendingIntent.getActivity(ctx, id, open, flags))
            }
            NotificationManagerCompat.from(ctx).notify(id, builder.build())
        } catch (_: Exception) {
            // no notification permission: ignore
        }
    }

    private fun signerHashes(pi: android.content.pm.PackageInfo): Set<String> {
        val out = HashSet<String>()
        val md = { b: ByteArray ->
            MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pi.signingInfo?.apkContentsSigners?.forEach { out.add(md(it.toByteArray())) }
        } else {
            @Suppress("DEPRECATION")
            pi.signatures?.forEach { out.add(md(it.toByteArray())) }
        }
        return out
    }

    private fun apkCompat(ctx: Context, path: String?): String {
        if (path == null) return "invalid"
        try {
            val pm = ctx.packageManager
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                PackageManager.GET_SIGNING_CERTIFICATES
            else
                @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
            val archive = pm.getPackageArchiveInfo(path, flags) ?: return "invalid"
            if (archive.packageName != ctx.packageName) return "package"
            val mine = pm.getPackageInfo(ctx.packageName, flags)
            val a = signerHashes(archive)
            val b = signerHashes(mine)
            if (a.isEmpty() || b.isEmpty()) return "ok" // cannot tell: let Android decide
            return if (a == b) "ok" else "signature"
        } catch (e: Exception) {
            return "ok"
        }
    }

    private fun onUnmeteredLink(ctx: Context): Boolean {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(net) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText(intent)?.let { shareChannel?.invokeMethod("onShared", it) }
        openKey(intent)?.let { shareChannel?.invokeMethod("onOpen", it) }
    }

    // "Share" -> SDM gives the link as text; tapping a link and choosing
    // SDM ("Open with") gives it as the intent data.
    private fun sharedText(i: Intent?): String? {
        if (i == null) return null
        return when (i.action) {
            Intent.ACTION_SEND -> i.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> {
                val u = i.data
                if (u != null && (u.scheme == "http" || u.scheme == "https")) u.toString() else null
            }
            else -> null
        }
    }

    private fun openKey(i: Intent?): String? = i?.getStringExtra(EXTRA_OPEN)
}
