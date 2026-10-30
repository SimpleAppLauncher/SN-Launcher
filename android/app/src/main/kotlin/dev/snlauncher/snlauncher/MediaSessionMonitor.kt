package dev.snlauncher.snlauncher

import android.content.ComponentName
import android.content.Context
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Notices whatever is playing on the device, whoever is playing it.
 *
 * The brief was: play something in SoundCloud and have the card appear on the
 * launcher. That is not the app's own player being involved at all — it is the
 * system telling us about another app's audio session.
 *
 * Android publishes every active media session through
 * [MediaSessionManager.getActiveSessions]. This service exists because reading
 * that list requires the app to be a [NotificationListenerService]: the
 * sessions carry metadata and transport controls, so the system will not hand
 * them to an arbitrary app. The user grants it once, in Settings, and it is
 * revocable — which is the correct trade for something that can see what is
 * playing on a device.
 *
 * What this never does: play anything itself, or touch anything but the
 * session it is reporting on. And if the notification permission is not
 * granted, [sessionList] returns null and the caller falls back to our own
 * player — the card simply shows nothing, which is the honest failure.
 */
class MediaSessionListener : NotificationListenerService() {

    companion object {
        /// Set by the monitor so a permission toggle does not need a restart.
        @Volatile
        var bound: MediaSessionMonitor? = null
    }

    override fun onListenerConnected() {
        bound?.onListenerConnected()
    }

    override fun onListenerDisconnected() {
        bound?.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: android.service.notification.StatusBarNotification?) {
        // Not filtering on the notification package: a media notification is
        // not guaranteed to be posted at the moment playback starts, and a
        // session that appeared is worth noticing regardless of which
        // notification announced it.
        bound?.onSessionsMayHaveChanged()
    }

    override fun onNotificationRemoved(sbn: android.service.notification.StatusBarNotification?) {
        bound?.onSessionsMayHaveChanged()
    }
}

/**
 * Reads the system's active media sessions, pushes the interesting one to
 * Flutter, and writes transport commands back to that same controller.
 */
class MediaSessionMonitor(
    private val context: Context,
    messenger: BinaryMessenger,
) {

    companion object {
        const val CHANNEL = "dev.snlauncher/sessions"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var listening = false

    /**
     * The controller for the session currently shown, kept so a transport
     * button can write to the app that owns the audio. `getActiveSessions`
     * hands back MediaControllers rather than read-only sessions for exactly
     * this reason; throwing the controller away made the card display-only.
     */
    @Volatile
    private var currentController: MediaController? = null

    private data class Candidate(
        val controller: MediaController,
        val reading: Map<String, Any?>,
    )

    init {
        MediaSessionListener.bound = this
        // The Dart->native direction was missing entirely: the channel was
        // created but never given a handler, so every `invokeMethod` from Dart
        // — hasPermission, sessions — raised MissingPluginException. That made
        // hasPermission report false on a device where the user *had* granted
        // notification access, and the watcher never polled. So a Spotify
        // session could never reach the card, and nothing said why.
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasPermission())
                "sessions" -> result.success(best())
                "command" -> result.success(command(call.argument<String>("action") ?: ""))
                "openSettings" -> {
                    try {
                        context.startActivity(settingsIntent())
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Permission ───────────────────────────────────────────────────────────

    /**
     * Whether the user has granted notification access.
     *
     * Checked rather than assumed: the toggle can be revoked from Settings at
     * any time, and a launcher that keeps showing a stale track after access is
     * pulled would be lying about the state of the device.
     */
    fun hasPermission(): Boolean {
        val enabled = android.provider.Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val target = ComponentName(context, MediaSessionListener::class.java)
        return enabled.split(":").any { entry ->
            ComponentName.unflattenFromString(entry)?.let {
                it.packageName == target.packageName &&
                    it.className == target.className
            } == true
        }
    }

    /** An intent that takes the user straight to the notification-access toggle. */
    fun settingsIntent(): android.content.Intent =
        android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)

    // ── Sessions ─────────────────────────────────────────────────────────────

    /**
     * The session most worth showing.
     *
     * "Most worth" is not "most recently active" alone. A paused session left
     * over from something the user finished an hour ago should not outrank the
     * thing actually playing, so a playing session always beats a paused one.
     */
    fun best(): Map<String, Any?>? {
        val manager =
            context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return null
        val listener = ComponentName(context, MediaSessionListener::class.java)
        val sessions = try {
            manager.getActiveSessions(listener)
        } catch (_: SecurityException) {
            // Permission not granted. Returning null is correct: the caller
            // falls back and the card shows nothing rather than guessing.
            currentController = null
            return null
        } ?: run {
            currentController = null
            return null
        }

        val candidates = sessions.mapNotNull { c ->
            describe(c)?.let { Candidate(c, it) }
        }
        if (candidates.isEmpty()) {
            currentController = null
            return null
        }
        val chosen = candidates.maxWithOrNull(
            compareBy<Candidate> { (it.reading["playing"] as? Boolean) == true }
                .thenBy { (it.reading["positionMs"] as? Long) ?: 0L },
        )
        currentController = chosen?.controller
        return chosen?.reading
    }

    /**
     * Sends one transport command to the session currently on screen.
     *
     * Capability-checked against the actions the other app published. Returns
     * false rather than pretending a command was accepted: the card keeps its
     * last real state, and a button that the app did not advertise is never
     * drawn in the first place.
     */
    fun command(action: String): Boolean {
        val c = currentController ?: return false
        val transport = c.transportControls ?: return false
        val state = try {
            c.playbackState
        } catch (_: Exception) {
            null
        } ?: return false
        val actions = state.actions
        // A session can disappear between the choose and the press. A failed
        // write is reported as false, never as an optimistic state.
        return try {
            when (action) {
                "play" -> {
                    val supported = actions and
                        (PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PLAY_PAUSE) != 0L
                    if (!supported) return false
                    transport.play()
                    true
                }
                "pause" -> {
                    val supported = actions and
                        (PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE) != 0L
                    if (!supported) return false
                    transport.pause()
                    true
                }
                "next" -> {
                    if (actions and PlaybackState.ACTION_SKIP_TO_NEXT == 0L) return false
                    transport.skipToNext()
                    true
                }
                "previous" -> {
                    if (actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS == 0L) return false
                    transport.skipToPrevious()
                    true
                }
                else -> false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun describe(session: MediaController): Map<String, Any?>? {
        // getActiveSessions hands back MediaControllers, not MediaSessions:
        // the controller is the write side, which is what makes the transport
        // buttons work on somebody else's playback rather than just displaying
        // its title.
        val meta = session.getMetadata() ?: return null
        val title = meta.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
        val artist = meta.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
        if (title.isNullOrBlank() && artist.isNullOrBlank()) return null

        val art = meta.getBitmap(android.media.MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: meta.getBitmap(android.media.MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        val artPath = art?.let { writeArtwork(it) } ?: ""

        val state = session.getPlaybackState()
        val actions = state?.actions ?: 0L
        val canPlay = actions and
            (PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PLAY_PAUSE) != 0L
        val canPause = actions and
            (PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE) != 0L
        val canNext = actions and PlaybackState.ACTION_SKIP_TO_NEXT != 0L
        val canPrevious = actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L
        val position = (state?.position ?: 0L)
        val duration = meta.getLong(
            android.media.MediaMetadata.METADATA_KEY_DURATION,
        ).takeIf { it > 0L } ?: 0L
        // Subtracting elapsed is the difference between a scrubber that is
        // roughly right and one that is minutes wrong after a pause.
        // `position` is the position as of the last state update, not now. Some
        // apps update it continuously and some only on pause, so it is advanced
        // by the elapsed delta. Without this the scrubber sits minutes behind
        // on a track that had been playing the whole time.
        // Verified against the SDK: PlaybackState exposes only
        // getLastPositionUpdateTime(), and it is on the elapsedRealtime clock.
        // The wall-clock variant does not exist, and pairing one with the other
        // would put every track decades out of position.
        val updatedAt = state?.getLastPositionUpdateTime() ?: 0L
        val elapsedSince = if (updatedAt > 0L) {
            (android.os.SystemClock.elapsedRealtime() - updatedAt).coerceAtLeast(0L)
        } else {
            0L
        }
        val resolved = if (state?.state == PlaybackState.STATE_PLAYING) {
            (position + elapsedSince).coerceAtLeast(0L)
        } else {
            position.coerceAtLeast(0L)
        }

        return mapOf(
            "package" to (session.getPackageName() ?: ""),
            "title" to (title ?: ""),
            "artist" to (artist ?: ""),
            "album" to (meta.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM) ?: ""),
            "artworkPath" to artPath,
            "playing" to (state?.state == PlaybackState.STATE_PLAYING),
            "loading" to (state?.state == PlaybackState.STATE_BUFFERING),
            "canPlay" to canPlay,
            "canPause" to canPause,
            "canNext" to canNext,
            "canPrevious" to canPrevious,
            "positionMs" to resolved,
            "durationMs" to duration,
        )
    }

    /**
     * Writes session artwork to the cache so Flutter can show it.
     *
     * Album art arrives as a bitmap inside the session, not as a URL, so it
     * has to be materialised. Returns an empty string rather than throwing:
     * an app with no artwork is normal, not an error.
     */
    private fun writeArtwork(bitmap: android.graphics.Bitmap): String {
        return try {
            val dir = java.io.File(context.cacheDir, "session_art")
            if (!dir.exists()) dir.mkdirs()
            val f = java.io.File(dir, "${bitmap.hashCode()}.png")
            if (!f.exists()) {
                java.io.FileOutputStream(f).use { bitmap.compress(
                    android.graphics.Bitmap.CompressFormat.PNG, 100, it,
                ) }
            }
            f.absolutePath
        } catch (_: Exception) {
            ""
        }
    }

    // ── Push ─────────────────────────────────────────────────────────────────

    fun onListenerConnected() {
        listening = true
        onSessionsMayHaveChanged()
    }

    fun onListenerDisconnected() {
        listening = false
        push(null)
    }

    /**
     * Polls rather than being pushed to.
     *
     * `MediaSessionManager` has no change callback; the notification listener
     * is the only hint available and it does not fire reliably when a session
     * appears. A short poll is the honest way to keep a card honest — the
     * alternative is a card that shows a track the user has already paused.
     */
    fun onSessionsMayHaveChanged() {
        // The notification callback only arrives while the listener is bound,
        // so `listening` is not a useful gate here — and it was actively
        // harmful when the activity attached after the service: the callback
        // fired, saw listening=false, and dropped the new track. Permission is
        // the only thing that decides whether reading is allowed.
        if (!hasPermission()) return
        executor.execute { push(best()) }
    }

    /** Called on a timer by the Dart side; see `onSessionsMayHaveChanged`. */
    fun poll() {
        if (!hasPermission()) {
            push(null)
            return
        }
        executor.execute { push(best()) }
    }

    private fun push(session: Map<String, Any?>?) {
        // Platform channel calls belong on the main thread. This used to be
        // invoked directly from the session executor, which meant a changed
        // track could be read and then silently never reach Dart. The Dart
        // poll masked it while the launcher was foregrounded; a backgrounded
        // launcher kept the old song until it was restarted.
        main.post {
            try {
                channel.invokeMethod("sessionChanged", session)
            } catch (_: Exception) {
                // Engine gone. Nothing to do.
            }
        }
    }

    fun dispose() {
        listening = false
        currentController = null
        MediaSessionListener.bound = null
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }
}
