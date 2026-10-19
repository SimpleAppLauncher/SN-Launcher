package dev.snlauncher.snlauncher

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * The Flutter side of [PlaybackService].
 *
 * A `MediaController` rather than poking the service directly: binding through
 * the session is what gives the launcher the same handle the system's own
 * controls use, so the notification, the lock screen and the in-app card can
 * never disagree about what is playing.
 *
 * Rebinding is the part worth care. The controller connects asynchronously and
 * may be torn down when the service dies, so every call checks for a live
 * connection rather than assuming one. A player that throws "not connected"
 * when you press play on a cold start looks exactly like a broken player.
 */
class PlaybackBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.snlauncher/playback"

        /// Whether a remote stream should show a progress bar at all.
        private const val EXTRA_LIVE = "live"
    }

    private lateinit var channel: MethodChannel
    private var controller: MediaController? = null
    private val executor: Executor = Executor { it.run() }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            // Push state to Dart so the launcher card follows the system
            // controls rather than the other way round.
            player.let { sendState() }
        }
    }

    fun attach(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        connect()
    }

    private fun connect() {
        val token =
            SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener(
            {
                try {
                    val c = future.get()
                    c.addListener(listener)
                    controller = c
                } catch (_: Exception) {
                    controller = null
                }
            },
            executor,
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val c = controller
        if (c == null && call.method != "available") {
            connect()
            // Reported, not thrown. A player that throws on a cold start is
            // indistinguishable from a player that is broken.
            result.success(mapOf("error" to "player is not connected yet"))
            return
        }

        try {
            when (call.method) {
                "available" -> result.success(true)
                "state" -> result.success(if (c == null) emptyMap<String, Any?>() else state(c))
                "play" -> {
                    val track = call.argument<Map<*, *>>("track")
                    // Built by hand rather than through listOf/mapNotNull: the
                    // generic inference over Map<*, *> chains is a swamp, and
                    // an explicit loop says exactly what it does.
                    val items = ArrayList<MediaItem>()
                    val queueArg = call.argument<List<*>>("queue").orEmpty()
                    if (queueArg.isEmpty()) {
                        if (track != null) itemFrom(track)?.let { items.add(it) }
                    } else {
                        for (raw in queueArg) {
                            if (raw is Map<*, *>) itemFrom(raw)?.let { items.add(it) }
                        }
                    }
                    if (items.isEmpty()) {
                        result.success(mapOf<String, Any?>(
                            "error" to "nothing playable was given"))
                        return
                    }
                    val index = (call.argument<Number>("index")?.toInt() ?: 0)
                        .coerceIn(0, items.size - 1)
                    c!!.setMediaItems(items, index, 0L)
                    c.prepare()
                    c.play()
                    result.success(state(c))
                }
                "resume" -> { c!!.play(); result.success(state(c)) }
                "pause" -> { c!!.pause(); result.success(state(c)) }
                "stop" -> { c!!.stop(); result.success(state(c)) }
                "next" -> {
                    if (c!!.hasNextMediaItem()) c.seekToNextMediaItem()
                    result.success(state(c))
                }
                "previous" -> {
                    c!!.seekToPreviousMediaItem()
                    result.success(state(c))
                }
                "seek" -> {
                    val ms = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    c!!.seekTo(ms)
                    result.success(state(c))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.success(mapOf("error" to (e.message ?: e.javaClass.simpleName)))
        }
    }

    private fun itemFrom(raw: Map<*, *>): MediaItem? {
        val url = raw["url"] as? String ?: return null
        if (url.isBlank()) return null
        return PlaybackService.buildItem(
            url = url,
            title = raw["title"] as? String,
            artist = raw["artist"] as? String,
            album = raw["album"] as? String,
            artworkUri = raw["artworkUrl"] as? String,
            durationMs = (raw["durationMs"] as? Number)?.toLong(),
            isLive = raw["isLive"] == true,
        )
    }

    private fun state(c: MediaController): Map<String, Any?> {
        val item: MediaItem? = c.currentMediaItem
        val meta = item?.mediaMetadata
        val live = meta?.extras?.getBoolean(EXTRA_LIVE, false) ?: false
        val error: String =
            c.playerError?.let { "Playback failed (${it.errorCodeName})" } ?: ""

        val track: Map<String, Any?>? = if (item == null) {
            null
        } else {
            mapOf(
                "url" to (item.requestMetadata.mediaUri?.toString() ?: ""),
                "title" to (meta?.title?.toString() ?: ""),
                "artist" to (meta?.artist?.toString() ?: ""),
                "album" to (meta?.albumTitle?.toString() ?: ""),
                "artworkUrl" to (meta?.artworkUri?.toString() ?: ""),
                "isLive" to live,
            )
        }

        return mapOf(
            "playing" to c.isPlaying,
            "loading" to (c.playbackState == Player.STATE_BUFFERING),
            "positionMs" to c.currentPosition.coerceAtLeast(0L),
            // A live stream reports no duration. Reporting zero rather than a
            // guess is what lets the Dart side hide the scrubber instead of
            // drawing a progress bar that will never finish.
            "durationMs" to (c.duration.takeIf { it > 0L } ?: 0L),
            "error" to error,
            "track" to track,
        )
    }

    /**
     * Pushes the current state to Dart whenever the player changes.
     *
     * This direction matters: the lock screen, a headset button and the
     * notification can all change playback, and the launcher's card has to
     * follow. Polling from Dart would show a card that disagrees with the
     * system controls until the next refresh.
     */
    private fun sendState() {
        val c = controller ?: return
        try {
            channel.invokeMethod("stateChanged", state(c))
        } catch (_: Exception) {
            // Dart not attached, or the engine is gone. Nothing to do.
        }
    }
}
