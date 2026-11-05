package dev.uaal.intercomm

import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import java.util.Locale
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

class UnityHost private constructor() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var port: UnityPlayerPort = EmbeddedUnityPlayer()
    private var ready = false
    private var concealed = false
    private var attached: FrameLayout? = null
    private var initializeTask: Deferred<Unit>? = null
    private var waiter: Waiter? = null
    private var errorSink: ((String) -> Unit)? = null
    private var errorSinkOp: String? = null

    fun installPlayer(port: UnityPlayerPort) {
        this.port = port
    }

    suspend fun initialize(activity: ComponentActivity) {
        withContext(Dispatchers.Main.immediate) {
            if (ready) return@withContext
            val existing = initializeTask
            if (existing != null) {
                existing.await()
                return@withContext
            }
            val task = scope.async { boot(activity) }
            initializeTask = task
            try {
                task.await()
            } catch (error: Throwable) {
                initializeTask = null
                throw error
            }
        }
    }

    suspend fun load() {
        command(event = "loaded", json = """{"op":"load"}""", timeoutMs = 60_000)
    }

    suspend fun loadPrefab(id: PrefabId) {
        val event = command(
            event = "prefabLoaded",
            json = """{"op":"loadPrefab","id":"${id.raw}"}""",
            timeoutMs = 120_000,
        )
        if (event.id != id.raw) {
            throw UnityHostError.Unexpected("prefab id が ${event.id ?: "空"} でした")
        }
    }

    fun setColor(r: Float, g: Float, b: Float) {
        sendExpectingNoError(
            op = "setColor",
            json = """{"op":"setColor","r":${number(r)},"g":${number(g)},"b":${number(b)}}""",
        )
    }

    fun setCamera(index: Int) {
        sendExpectingNoError(op = "setCamera", json = """{"op":"setCamera","index":$index}""")
    }

    fun onHostResume() {
        if (!concealed && attached != null) port.onHostResume()
    }

    fun onHostPause() {
        if (ready) port.onHostPause()
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        if (hasFocus && (concealed || attached == null)) return
        port.onWindowFocusChanged(hasFocus)
    }

    fun keepOffscreen() {
        val frame = attached
        attached = null
        if (frame != null) port.detach(frame)
        if (!concealed) {
            concealed = true
            port.pause()
        }
    }

    internal fun attach(frame: FrameLayout) {
        attached = frame
        if (concealed) {
            concealed = false
            port.resume()
        }
        port.attach(frame)
    }

    internal fun detach(frame: FrameLayout) {
        if (attached !== frame) return
        keepOffscreen()
    }

    internal fun handle(json: String) {
        val event = BridgeEvent.parse(json) ?: return
        if (event.event == "ready") ready = true
        if (event.event == "error") {
            if (errorSink != null && event.op == errorSinkOp) {
                errorSink?.invoke(event.message ?: "error")
            }
            val current = waiter
            if (current != null && current.event == eventName(event.op)) {
                finish(current, UnityHostError.Bridge(event.op ?: current.event, event.message ?: "error"))
            }
            return
        }
        val current = waiter
        if (current != null && current.event == event.event) {
            finish(current, event)
        }
    }

    private suspend fun boot(activity: ComponentActivity) {
        if (ready) return
        waitFor(event = "ready", timeoutMs = 90_000) {
            port.start(activity)
        }
        ready = true
    }

    private suspend fun command(event: String, json: String, timeoutMs: Long): BridgeEvent {
        if (!ready) throw UnityHostError.Bridge(event, "not ready")
        return waitFor(event, timeoutMs) { port.send(json) }
    }

    private fun sendExpectingNoError(op: String, json: String) {
        if (!ready) throw UnityHostError.Bridge(op, "not ready")
        var failure: UnityHostError? = null
        errorSinkOp = op
        errorSink = { message -> failure = UnityHostError.Bridge(op, message) }
        try {
            port.send(json)
        } finally {
            errorSink = null
            errorSinkOp = null
        }
        failure?.let { throw it }
    }

    private suspend fun waitFor(event: String, timeoutMs: Long, start: () -> Unit): BridgeEvent {
        try {
            return withTimeout(timeoutMs) {
                suspendCancellableCoroutine { continuation ->
                    val next = Waiter(event, continuation)
                    waiter = next
                    continuation.invokeOnCancellation {
                        if (waiter === next) waiter = null
                    }
                    try {
                        start()
                    } catch (error: Throwable) {
                        finish(next, error)
                    }
                }
            }
        } catch (timeout: TimeoutCancellationException) {
            throw UnityHostError.TimedOut(event)
        }
    }

    private fun finish(waiter: Waiter, event: BridgeEvent) {
        if (waiter.finished) return
        waiter.finished = true
        if (this.waiter === waiter) this.waiter = null
        waiter.continuation.resume(event)
    }

    private fun finish(waiter: Waiter, error: Throwable) {
        if (waiter.finished) return
        waiter.finished = true
        if (this.waiter === waiter) this.waiter = null
        waiter.continuation.resumeWithException(error)
    }

    private fun eventName(op: String?): String? {
        return when (op) {
            "load" -> "loaded"
            "loadPrefab" -> "prefabLoaded"
            else -> null
        }
    }

    private fun number(value: Float): String {
        return String.format(Locale.US, "%.6f", value)
    }

    private class Waiter(
        val event: String,
        val continuation: Continuation<BridgeEvent>,
    ) {
        var finished = false
    }

    private data class BridgeEvent(
        val event: String,
        val id: String?,
        val op: String?,
        val message: String?,
    ) {
        companion object {
            fun parse(json: String): BridgeEvent? {
                val objectJson = runCatching { JSONObject(json) }.getOrNull() ?: return null
                val event = objectJson.optString("event").takeIf { it.isNotEmpty() } ?: return null
                return BridgeEvent(
                    event = event,
                    id = objectJson.optString("id").takeIf { it.isNotEmpty() },
                    op = objectJson.optString("op").takeIf { it.isNotEmpty() },
                    message = objectJson.optString("message").takeIf { it.isNotEmpty() },
                )
            }
        }
    }

    companion object {
        val shared = UnityHost()
    }
}
