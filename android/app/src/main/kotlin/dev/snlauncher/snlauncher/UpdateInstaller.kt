package dev.snlauncher.snlauncher

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/**
 * The native half of the updater.
 *
 * Three questions, and only this side can answer them:
 *
 *  * what this build is — its version, its package, its ABI, and who put it
 *    here;
 *  * whether a downloaded file is this app's own newer build;
 *  * whether Android will let this app install it.
 *
 * The signature check is the one that matters. An update that is not signed
 * with the same key as the installed app is not an update, it is somebody
 * else's file, and Android will refuse it anyway. Checking it here means the
 * refusal is a sentence the user can read instead of a stack trace.
 */
object UpdateInstaller {
    /**
     * What this build is.
     *
     * Null when the package manager cannot say, which is a desktop build or
     * an Android whose native side is not there. The caller must read that as
     * "this build cannot update itself", never as "there is no update".
     */
    fun appInfo(context: Context): Map<String, Any?>? = try {
        val pm = context.packageManager
        val info = pm.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCodeOf(info),
            "applicationId" to context.packageName,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
            "installer" to installerOf(context),
            "canInstallPackages" to canInstallPackages(context),
            // The files directory, not the cache: Android may clear the cache
            // at any time, and the installer is handed this file.
            "filesDir" to context.filesDir.absolutePath,
        )
    } catch (_: Exception) {
        null
    }

    /**
     * Whether the file at [path] is this app's own newer build.
     *
     * Three checks, and the reason names the one that failed. "Corrupt" would
     * be a lie: a file signed with another key is perfectly good, it is just
     * not this app's.
     */
    fun verify(context: Context, path: String): Map<String, Any> {
        val pm = context.packageManager
        val file = File(path)
        if (!file.exists()) {
            return refusal("The download is missing.")
        }

        val candidate = try {
            pm.getPackageArchiveInfo(file.absolutePath, PackageManager.GET_SIGNING_CERTIFICATES)
        } catch (_: Exception) {
            null
        } ?: return refusal("The download is not an installable app.")

        val installed = try {
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } catch (_: Exception) {
            null
        } ?: return refusal("Could not read this build's own signature.")

        // 1. The package name. A file for another app is not an update.
        if (candidate.packageName != context.packageName) {
            return refusal(
                "This file is ${candidate.packageName}, not ${context.packageName}."
            )
        }

        // 2. The signing key. This is the check that matters.
        val mine = currentSigners(installed)
        if (mine.isEmpty()) {
            return refusal("Could not read this build's own signature.")
        }
        val theirs = currentSigners(candidate)
        if (theirs.isEmpty()) {
            return refusal("Could not read the signature of the download.")
        }
        if (mine != theirs) {
            return refusal(
                "This file was signed with a different key, so it is not an " +
                    "update of this app."
            )
        }

        // 3. The version. An older build is not an update either.
        if (!isNewer(candidate.versionName, installed.versionName)) {
            return refusal(
                "This file is version ${candidate.versionName ?: "?"}, which is " +
                    "not newer than the build you are running."
            )
        }

        return mapOf("ok" to true, "reason" to "")
    }

    /**
     * Hands the file at [path] to Android's installer.
     *
     * When the app is not allowed to install packages, nothing is started and
     * the reason says so: the fix is a setting the user opens, and a sentence
     * that names it is more use than "failed".
     */
    /**
     * Opens the screen where the user grants this app permission to install
     * packages from outside the store.
     *
     * Android 8 and later ask for that per app, and the screen is where the
     * answer has to be given — there is no runtime dialog for it. The package
     * is carried in the data URI, which is the documented way to land on this
     * app's own entry rather than on the list of all of them.
     */
    fun openInstallSettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            // No screen to open. The caller says so rather than pretending.
            false
        }
    }

    fun install(context: Context, path: String): Map<String, Any> {
        if (!canInstallPackages(context)) {
            return mapOf(
                "started" to false,
                "reason" to "SN-Launcher needs permission to install updates.",
                // The refusal is the one the user can fix: there is a screen
                // where that permission is granted, and the app has to be
                // able to send the user there. Without this flag the refusal
                // is a dead end.
                "needsPermission" to true,
            )
        }

        val file = File(path)
        if (!file.exists()) {
            return mapOf("started" to false, "reason" to "The download is missing.")
        }

        return try {
            val uri: Uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.updates",
                file,
            )
            // ACTION_VIEW with the archive type is the form every Android
            // package installer answers. ACTION_INSTALL_PACKAGE is the
            // documented one, but it is not what the stock resolver matches
            // on a real device, and an intent that resolves to nothing is an
            // update that silently does not happen.
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            mapOf("started" to true, "reason" to "")
        } catch (e: Exception) {
            mapOf(
                "started" to false,
                "reason" to "Android did not open the installer: ${e.message}",
            )
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun refusal(reason: String): Map<String, Any> =
        mapOf("ok" to false, "reason" to reason)

    private fun versionCodeOf(info: PackageInfo): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode
        }

    /** Who installed this build, or an empty string when nobody claims it. */
    private fun installerOf(context: Context): String = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager
                .getInstallSourceInfo(context.packageName)
                .installingPackageName
                ?: ""
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstallerPackageName(context.packageName) ?: ""
        }
    } catch (_: Exception) {
        ""
    }

    /** Whether the user has let this app install packages. */
    private fun canInstallPackages(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                context.packageManager.canRequestPackageInstalls()
            } catch (_: Exception) {
                false
            }
        } else {
            true
        }

    /**
     * The certificates this build is signed with, as SHA-256 digests.
     *
     * The *current* signer, not the whole history: a key that has been
     * rotated away from is not a key that can sign an update this app will
     * accept, and comparing histories would accept a file signed with the
     * old key.
     */
    private fun currentSigners(info: PackageInfo): List<String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo ?: return emptyList()
            // `apkContentsSigners`, not `signingCertificateHistory`.
            //
            // The history is an *installed app's* lineage: it says which key
            // signed the app and which key took over from it. An APK read off
            // the disk with `getPackageArchiveInfo` has no lineage, so its
            // history comes back **empty** — and an empty history read as "no
            // signer" refused every update on the first try, on the phone.
            //
            // `apkContentsSigners` is the certificate that signed *this* APK,
            // which is the thing being compared, and it is filled in for both
            // an installed app and an archive. For a key rotation it is the
            // current key, not the retired one, which is what we want: a
            // retired key must not be able to sign an update this app accepts.
            return signing.apkContentsSigners.map { digest(it.toByteArray()) }.sorted()
        }
        @Suppress("DEPRECATION")
        return info.signatures?.map { digest(it.toByteArray()) }?.sorted() ?: emptyList()
    }

    private fun digest(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    /**
     * Whether [candidate] is a newer version than [installed].
     *
     * The numeric triple, and only the triple: a pre-release of the same
     * version is not newer, and neither is a version with a suffix this side
     * cannot compare. Version *codes* are not compared either — Flutter adds
     * a per-ABI offset to them, so a universal APK looks older than the
     * arm64 build of the same release.
     */
    private fun isNewer(candidate: String?, installed: String?): Boolean {
        val a = versionParts(candidate)
        val b = versionParts(installed)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }

    private fun versionParts(version: String?): List<Int> {
        val core = (version ?: "").substringBefore('-').trim()
        if (core.isEmpty()) return emptyList()
        return core.split('.').map { it.toIntOrNull() ?: 0 }
    }
}
