package com.mars.mars_app

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/// "mars/installer" for the app updater (lib/core/updater.dart):
///   canInstall           -> is "Install unknown apps" allowed for MARS (always true before Android 8)
///   openInstallSettings  -> opens that setting for MARS
///   signers {path}       -> SHA-256 of the signing certificates: {installed: [...], apk: [...]}
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mars/installer").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> try {
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                "signers" -> {
                    val path = call.argument<String>("path")!!
                    result.success(mapOf(
                        "installed" to signers(packageManager.getPackageInfo(packageName, signingFlag)),
                        "apk" to signers(packageManager.getPackageArchiveInfo(path, signingFlag)),
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private val signingFlag =
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo?): List<String> {
        val sigs = if (Build.VERSION.SDK_INT >= 28) info?.signingInfo?.apkContentsSigners else info?.signatures
        return sigs?.map { s ->
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
        } ?: emptyList()
    }
}
