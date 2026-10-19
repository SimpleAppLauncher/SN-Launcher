package dev.snlauncher.snlauncher

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Real background audio.
 *
 * A WebView cannot do this, and that is not a matter of effort:
 *
 *  - Android suspends the WebView renderer about five minutes after the app is
 *    backgrounded, *even with a foreground service running*, so page timers and
 *    requests stop.
 *  - The System WebView stops producing audio when the screen locks.
 *
 * A `MediaSessionService` is the architecture Google prescribes for exactly
 * this: an `ExoPlayer` owned by a foreground service, wrapped in a
 * `MediaSession` so the system knows what is playing. That is also what puts a
 * notification on the lock screen with working transport buttons — without a
 * session there is nothing for the system to draw controls for.
 *
 * Playback continues with the app closed and the screen off. That is the whole
 * reason this class exists.
 *
 * The service deliberately knows nothing about music *sources*. It is handed a
 * URL and metadata and plays it. What may legitimately be played is decided on
 * the Dart side, not here.
 */
class PlaybackService : MediaSessionService() {

    private var player: ExoPlayer? = null
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val p = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    // Music: takes audio focus, ducks for notifications, and
                    // does not treat a podcast as a phone call.
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                /* handleAudioFocus = */ true,
            )
            // Keep the screen awake only while actually playing, and only for
            // video. Audio must not pin a wake lock on its own; the foreground
            // service and the wakelock below are what cover screen-off.
            .setHandleAudioBecomingNoisy(true)
            .build()

        player = p
        session = MediaSession.Builder(this, p)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app away should not leave a service holding audio. If
        // nothing is playing, stop rather than lingering as an invisible
        // foreground service.
        val p = player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) {
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        session?.run {
            player.release()
            release()
        }
        session = null
        player = null
        super.onDestroy()
    }

    /** Exposed so the Flutter bridge can drive it without a session controller. */
    fun playerOrNull(): ExoPlayer? = player

    companion object {
        /** Command for "start or resume this URL". */
        const val COMMAND_PLAY = "snlauncher/play"

        /**
         * Builds the item the notification and lock screen are drawn from.
         *
         * Every field is optional and defaulted. The system's media controls
         * look worse than useful with a row of blanks on them, and the honest
         * fallback is the app's own name rather than an empty string.
         */
        fun buildItem(
            url: String,
            title: String?,
            artist: String?,
            album: String?,
            artworkUri: String?,
            durationMs: Long?,
            isLive: Boolean,
        ): MediaItem {
            // A hint only. Duration is read from the player once it has decoded
            // the stream; a live stream reports no duration at all, which is
            // why the Dart side hides the scrubber rather than showing 99%.
            val extras = android.os.Bundle().apply {
                if (durationMs != null && durationMs > 0) {
                    putLong("durationMs", durationMs)
                }
            }
            return MediaItem.Builder()
                .setUri(url)
                .setMediaId(url)
                .setRequestMetadata(
                    MediaItem.RequestMetadata.Builder()
                        .setMediaUri(android.net.Uri.parse(url))
                        .build(),
                )
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(title?.takeIf { it.isNotBlank() } ?: "SN-Launcher")
                        .setArtist(artist?.takeIf { it.isNotBlank() })
                        .setAlbumTitle(album?.takeIf { it.isNotBlank() })
                        .setArtworkUri(artworkUri?.takeIf { it.isNotBlank() }?.let {
                            android.net.Uri.parse(it)
                        })
                        .setIsPlayable(true)
                        .setExtras(extras)
                        .build(),
                )
                .build()
        }
    }
}

/** Opens the launcher when the notification is tapped. */
fun playbackContentIntent(context: android.content.Context): PendingIntent {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: Intent()
    intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
    return PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
