package dev.snlauncher.snlauncher

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioManager
import android.net.Uri
import android.os.Bundle
import android.os.Looper
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

/** Provides the Android capabilities that the launcher shell exposes to Flutter. */
class PlatformBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val pendingPermissionResults = mutableMapOf<Int, MethodChannel.Result>()
    private var nextRequestCode = REQUEST_CODE_START

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setBrightness" -> setBrightness(call, result)
            "getBrightness" -> getBrightness(result)
            "setVolume" -> setVolume(call, result)
            "getVolume" -> getVolume(result)
            "openAppSettings" -> openAppSettings(result)
            "listApps" -> listApps(result)
            "launchApp" -> launchApp(call, result)
            "hasCamera" -> hasCamera(result)
            "openCamera" -> openCamera(result)
            "requestPermission" -> requestPermission(call, result)
            "getLocation" -> getLocation(result)
            "upcomingEvents" -> upcomingEvents(call, result)
            "openUrl" -> openUrl(call, result)
            "mediaKey" -> mediaKey(call, result)
            "setTimerLabel" -> setTimerLabel(call, result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        val result = pendingPermissionResults.remove(requestCode) ?: return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result.success(mapOf("granted" to granted))
    }

    private fun setBrightness(call: MethodCall, result: MethodChannel.Result) {
        val value = (call.argument<Number>("value")?.toFloat() ?: rememberedBrightness)
            .coerceIn(0f, 1f)
        activity.runOnUiThread {
            try {
                val attributes = activity.window.attributes.apply { screenBrightness = value }
                activity.window.attributes = attributes
                rememberedBrightness = value

                // WRITE_SETTINGS is deliberately optional: kiosk devices often deny it.
                if (Settings.System.canWrite(activity)) {
                    Settings.System.putInt(
                        activity.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS_MODE,
                        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
                    )
                }
                result.success(mapOf("value" to value.toDouble()))
            } catch (_: Exception) {
                result.success(mapOf("value" to rememberedBrightness.toDouble()))
            }
        }
    }

    private fun getBrightness(result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                val brightness = activity.window.attributes.screenBrightness
                val value = if (brightness == WindowBrightness.SYSTEM_DEFAULT) rememberedBrightness else brightness
                result.success(mapOf("value" to value.toDouble()))
            } catch (_: Exception) {
                result.success(mapOf("value" to rememberedBrightness.toDouble()))
            }
        }
    }

    private fun setVolume(call: MethodCall, result: MethodChannel.Result) {
        try {
            val audio = activity.getSystemService(Activity.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val value = (call.argument<Number>("value")?.toDouble() ?: 0.0).coerceIn(0.0, 1.0)
            val index = (value * max).roundToInt()
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
            result.success(mapOf("value" to index, "max" to max))
        } catch (_: Exception) {
            result.success(mapOf("value" to 0, "max" to 0))
        }
    }

    private fun getVolume(result: MethodChannel.Result) {
        try {
            val audio = activity.getSystemService(Activity.AUDIO_SERVICE) as AudioManager
            result.success(
                mapOf(
                    "value" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
                    "max" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                ),
            )
        } catch (_: Exception) {
            result.success(mapOf("value" to 0, "max" to 0))
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                activity.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(mapOf("opened" to true))
            } catch (_: Exception) {
                result.success(mapOf("opened" to false))
            }
        }
    }

    /**
     * Every app that advertises a launcher activity, with the icon the app
     * itself supplies.
     *
     * This runs off the main thread because icon rasterisation touches
     * resources for every installed package, and doing that on the UI thread
     * on a UNISOC tablet drops frames before the launcher has even appeared.
     * The result is a list of maps so the Dart side can keep its own model and
     * tests do not need to know about Android classes.
     */
    private fun listApps(result: MethodChannel.Result) {
        Thread {
            val apps = mutableListOf<Map<String, Any>>()
            try {
                val pm = activity.packageManager
                // Tablets use CATEGORY_LAUNCHER. Leanback-only apps — the
                // normal case on a TV — advertise CATEGORY_LEANBACK_LAUNCHER
                // instead and would otherwise leave the TV drawer empty.
                val launcherIntents = listOf(
                    Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
                    Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER),
                )
                val seen = HashSet<String>()
                for (launcherIntent in launcherIntents) {
                    for (info in pm.queryIntentActivities(launcherIntent, 0)) {
                        val packageName = info.activityInfo?.packageName ?: continue
                        if (packageName == activity.packageName || !seen.add(packageName)) continue

                        val label = try {
                            info.loadLabel(pm).toString().trim()
                        } catch (_: Exception) {
                            ""
                        }
                        if (label.isEmpty()) continue

                        val iconBytes = try {
                            drawableToPng(info.loadIcon(pm))
                        } catch (_: Exception) {
                            null
                        }

                        val row = mutableMapOf<String, Any>(
                            "package" to packageName,
                            "label" to label,
                        )
                        if (iconBytes != null) row["icon"] = iconBytes
                        apps.add(row)
                    }
                }
                apps.sortWith(
                    compareBy { (it["label"] as? String ?: "").lowercase(Locale.getDefault()) },
                )
                activity.runOnUiThread {
                    result.success(mapOf("apps" to apps))
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    result.success(mapOf("apps" to emptyList<Map<String, Any>>()))
                }
            }
        }.start()
    }

    /**
     * Launches an installed package.
     *
     * `getLaunchIntentForPackage` is the tablet path. The leanback fallback is
     * for the TV build: a leanback-only app has no ordinary launcher intent,
     * but it is still an app the user can see and choose.
     */
    private fun launchApp(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("package")?.trim().orEmpty()
        if (packageName.isEmpty()) {
            result.success(mapOf("opened" to false))
            return
        }
        activity.runOnUiThread {
            try {
                val pm = activity.packageManager
                val intent = pm.getLaunchIntentForPackage(packageName)
                    ?: pm.getLeanbackLaunchIntentForPackage(packageName)
                if (intent == null) {
                    result.success(mapOf("opened" to false))
                } else {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                    result.success(mapOf("opened" to true))
                }
            } catch (_: Exception) {
                result.success(mapOf("opened" to false))
            }
        }
    }

    private fun drawableToPng(drawable: Drawable): ByteArray? {
        // 144 px is enough for the sheet's 80 dp badge at 1.8x density without
        // keeping a full-resolution icon for every installed app in memory.
        val edge = 144
        val bitmap = Bitmap.createBitmap(edge, edge, Bitmap.Config.ARGB_8888)
        return try {
            drawable.setBounds(0, 0, edge, edge)
            drawable.draw(Canvas(bitmap))
            val out = ByteArrayOutputStream()
            if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) out.toByteArray() else null
        } finally {
            bitmap.recycle()
        }
    }

    private fun hasCamera(result: MethodChannel.Result) {
        try {
            result.success(
                mapOf("available" to activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)),
            )
        } catch (_: Exception) {
            result.success(mapOf("available" to false))
        }
    }

    private fun openCamera(result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
                    result.success(mapOf("opened" to false, "reason" to "no camera hardware"))
                    return@runOnUiThread
                }
                val intents = listOf(
                    Intent(MediaStore.ACTION_IMAGE_CAPTURE),
                    Intent("android.media.action.STILL_IMAGE_CAMERA"),
                    Intent("camera"),
                )
                val intent = intents.firstOrNull { it.resolveActivity(activity.packageManager) != null }
                if (intent == null) {
                    result.success(mapOf("opened" to false, "reason" to "no camera app"))
                } else {
                    activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(mapOf("opened" to true, "reason" to ""))
                }
            } catch (_: SecurityException) {
                result.success(mapOf("opened" to false, "reason" to "permission denied"))
            } catch (error: Exception) {
                result.success(mapOf("opened" to false, "reason" to (error::class.java.simpleName.ifEmpty { "Exception" })))
            }
        }
    }

    /**
     * The device's own location.
     *
     * The network provider first, then GPS. On a device with WiFi the network
     * provider is derived from the access points, which is what a wall-mounted
     * tablet actually wants: fast, indoor-friendly, and it does not need a view
     * of the sky. GPS is the fallback for when there is no WiFi to work from.
     *
     * A last known fix is preferred over a fresh request — it is instant, and
     * on a device that has moved in the last half hour it is as good as a new
     * one for weather. With no usable last known fix, a single fresh update is
     * requested, with a timeout so the caller is never left waiting.
     */
    private fun getLocation(result: MethodChannel.Result) {
        try {
            if (ActivityCompat.checkSelfPermission(
                    activity, Manifest.permission.ACCESS_COARSE_LOCATION
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                result.success(mapOf("ok" to false, "reason" to "permission"))
                return
            }
            val manager =
                activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            if (manager == null) {
                result.success(mapOf("ok" to false, "reason" to "no_service"))
                return
            }

            val fresh = lastKnown(manager)
            if (fresh != null && System.currentTimeMillis() - fresh.time < STALE_LOCATION_MS) {
                result.success(locationPayload(fresh, "cached"))
                return
            }

            // No usable last known fix: ask for one, and give up after a while
            // rather than leaving the caller waiting.
            val answered = AtomicBoolean(false)
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (answered.compareAndSet(false, true)) {
                        try {
                            manager.removeUpdates(this)
                        } catch (_: Exception) {
                        }
                        result.success(locationPayload(location, "fresh"))
                    }
                }

                override fun onProviderEnabled(provider: String) {
                }

                override fun onProviderDisabled(provider: String) {
                }
            }

            var requested = false
            for (provider in listOf(
                    LocationManager.NETWORK_PROVIDER,
                    LocationManager.GPS_PROVIDER
                )
            ) {
                try {
                    manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                    requested = true
                    break
                } catch (_: Exception) {
                    // This provider is not available; try the next one.
                }
            }
            if (!requested) {
                result.success(mapOf("ok" to false, "reason" to "no_provider"))
                return
            }

            activity.window.decorView.postDelayed({
                if (answered.compareAndSet(false, true)) {
                    try {
                        manager.removeUpdates(listener)
                    } catch (_: Exception) {
                    }
                    result.success(mapOf("ok" to false, "reason" to "timeout"))
                }
            }, LOCATION_TIMEOUT_MS)
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "reason" to e::class.java.simpleName))
        }
    }

    private fun lastKnown(manager: LocationManager): Location? {
        var best: Location? = null
        for (provider in listOf(
                LocationManager.NETWORK_PROVIDER,
                LocationManager.GPS_PROVIDER,
                LocationManager.PASSIVE_PROVIDER
            )
        ) {
            val loc = try {
                manager.getLastKnownLocation(provider)
            } catch (_: Exception) {
                null
            }
            if (loc != null && (best == null || loc.time > best!!.time)) best = loc
        }
        return best
    }

    private fun locationPayload(location: Location, source: String) = mapOf(
        "ok" to true,
        "lat" to location.latitude,
        "lon" to location.longitude,
        "accuracy" to location.accuracy.toDouble(),
        "source" to source
    )

    private fun requestPermission(call: MethodCall, result: MethodChannel.Result) {
        val permission = when (call.argument<String>("permission")) {
            "calendar" -> Manifest.permission.READ_CALENDAR
            "camera" -> Manifest.permission.CAMERA
            "location" -> Manifest.permission.ACCESS_COARSE_LOCATION
            else -> null
        }
        if (permission == null) {
            result.success(mapOf("granted" to false))
            return
        }
        try {
            if (ActivityCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
                result.success(mapOf("granted" to true))
                return
            }
            val requestCode = nextRequestCode++
            pendingPermissionResults[requestCode] = result
            activity.runOnUiThread {
                try {
                    ActivityCompat.requestPermissions(activity, arrayOf(permission), requestCode)
                } catch (_: Exception) {
                    pendingPermissionResults.remove(requestCode)?.success(mapOf("granted" to false))
                }
            }
        } catch (_: Exception) {
            result.success(mapOf("granted" to false))
        }
    }

    private fun upcomingEvents(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (ActivityCompat.checkSelfPermission(activity, Manifest.permission.READ_CALENDAR) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                result.success(mapOf("events" to emptyList<Map<String, Any>>()))
                return
            }
            val limit = (call.argument<Number>("limit")?.toInt() ?: 0).coerceAtLeast(0)
            val fromMillis = call.argument<Number>("fromMillis")?.toLong() ?: 0L
            val uri = ContentUris.appendId(
                ContentUris.appendId(CalendarContract.Instances.CONTENT_URI.buildUpon(), fromMillis),
                Long.MAX_VALUE,
            ).build()
            val events = mutableListOf<Map<String, Any>>()
            var cursor: android.database.Cursor? = null
            try {
                cursor = activity.contentResolver.query(
                    uri,
                    EVENT_PROJECTION,
                    "${CalendarContract.Instances.BEGIN} >= ?",
                    arrayOf(fromMillis.toString()),
                    "${CalendarContract.Instances.BEGIN} ASC",
                )
                while (cursor != null && cursor.moveToNext() && events.size < limit) {
                    val title = cursor.getString(0)?.trim().orEmpty()
                    if (title.isBlank()) continue
                    events += mapOf(
                        "title" to title,
                        "start" to cursor.getLong(1),
                        "end" to cursor.getLong(2),
                        "location" to (cursor.getString(3) ?: ""),
                        "allDay" to (cursor.getInt(4) == 1),
                        "color" to if (cursor.isNull(5)) DEFAULT_EVENT_COLOR else cursor.getInt(5),
                    )
                }
            } finally {
                cursor?.close()
            }
            result.success(mapOf("events" to events))
        } catch (_: Exception) {
            result.success(mapOf("events" to emptyList<Map<String, Any>>()))
        }
    }

    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                val url = call.argument<String>("url") ?: ""
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(activity.packageManager) == null) {
                    result.success(mapOf("opened" to false))
                } else {
                    activity.startActivity(intent)
                    result.success(mapOf("opened" to true))
                }
            } catch (_: Exception) {
                result.success(mapOf("opened" to false))
            }
        }
    }

    /**
     * Raises a hardware media key.
     *
     * This is how the assistant's "play music" / "pause" actually start
     * something. Injecting KEYCODE_MEDIA_PLAY_PAUSE reaches whatever player the
     * user already has, including the system media session, without this app
     * needing to know or bundle any of it — which is what keeps the APK at
     * 17 MB rather than shipping a media stack.
     *
     * Returns ok:false when the platform refuses, so the assistant reports that
     * rather than claiming music started.
     */
    private fun mediaKey(call: MethodCall, result: MethodChannel.Result) {
        try {
            val action = call.argument<String>("action") ?: "play"
            val keyCode = when (action) {
                "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            }
            // A media key needs DOWN then UP; a lone KeyEvent is ignored by
            // most receivers.
            dispatchKeyEvent(keyCode)
            result.success(mapOf("ok" to true))
        } catch (_: Exception) {
            result.success(mapOf("ok" to false))
        }
    }

    /**
     * Injects a media key through [AudioManager], not [Activity.dispatchEvent].
     *
     * `dispatchEvent` is protected on Activity and is not callable from here,
     * and the usual workaround — `Instrumentation.sendKeyDownUpSync` — needs the
     * signature-level INJECT_EVENTS permission, which a normal app cannot hold.
     * `AudioManager.dispatchMediaKeyEvent` is public since API 19, needs no
     * permission, and reaches exactly the same media session.
     */
    private fun dispatchKeyEvent(keyCode: Int) {
        val audio = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
    }

    /** Records a countdown label so the launcher can show it. */
    private fun setTimerLabel(call: MethodCall, result: MethodChannel.Result) {
        try {
            val label = call.argument<String>("label").orEmpty()
            result.success(mapOf("ok" to label.isNotBlank()))
        } catch (_: Exception) {
            result.success(mapOf("ok" to false))
        }
    }

    private object WindowBrightness {
        const val SYSTEM_DEFAULT = -1f
    }

    private companion object {
        const val CHANNEL_NAME = "dev.snlauncher/platform"
        const val REQUEST_CODE_START = 4100
        const val DEFAULT_EVENT_COLOR = 0xFF4285F4.toInt()

        // A last known fix older than half an hour is not much use for weather.
        const val STALE_LOCATION_MS = 30L * 60L * 1000L

        // How long to wait for a fresh fix before giving up. The caller is
        // never left hanging.
        const val LOCATION_TIMEOUT_MS = 8000L
        val EVENT_PROJECTION = arrayOf(
            CalendarContract.Instances.TITLE,
            // BEGIN/END, *not* DTSTART/DTEND.
            //
            // On the Instances view every row repeats the parent event's
            // DTSTART/DTEND, while BEGIN/END are the times of that particular
            // occurrence. Reading DTSTART returns a daily event's original start
            // date on every row — which surfaced as the digest page showing the
            // same event three times, dated a year in the past, all stamped
            // "20:00" because only the clock component was being formatted.
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_COLOR,
        )

        // Window brightness is per-activity, so remember it across recreation.
        var rememberedBrightness = 1f
    }
}
