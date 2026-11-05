package dev.uaal.intercomm

import android.widget.FrameLayout
import androidx.activity.ComponentActivity

interface UnityPlayerPort {
    fun start(activity: ComponentActivity)

    fun send(json: String)

    fun pause()

    fun resume()

    fun attach(container: FrameLayout)

    fun detach(container: FrameLayout)

    fun onHostResume()

    fun onHostPause()

    fun onWindowFocusChanged(hasFocus: Boolean)
}

internal class UnavailableUnityPlayerPort : UnityPlayerPort {
    override fun start(activity: ComponentActivity) {
        throw UnityHostError.MissingRuntime()
    }

    override fun send(json: String) = Unit

    override fun pause() = Unit

    override fun resume() = Unit

    override fun attach(container: FrameLayout) = Unit

    override fun detach(container: FrameLayout) = Unit

    override fun onHostResume() = Unit

    override fun onHostPause() = Unit

    override fun onWindowFocusChanged(hasFocus: Boolean) = Unit
}
