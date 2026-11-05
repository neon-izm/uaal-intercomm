package dev.uaal.intercomm

import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import com.unity3d.player.UnityPlayer
import com.unity3d.player.UnityPlayerForActivityOrService

internal class EmbeddedUnityPlayer : UnityPlayerPort {
    private var player: UnityPlayerForActivityOrService? = null
    private var parking: FrameLayout? = null

    override fun start(activity: ComponentActivity) {
        if (player != null) return
        val created = UnityPlayerForActivityOrService(activity)
        val view = created.playerView()
        (view.parent as? ViewGroup)?.removeView(view)
        val holder = FrameLayout(activity).apply { alpha = 0f }
        activity.addContentView(
            holder,
            FrameLayout.LayoutParams(64, 64).apply {
                gravity = Gravity.START or Gravity.TOP
            },
        )
        holder.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        parking = holder
        player = created
        created.resume()
        created.onResume()
        created.windowFocusChanged(true)
    }

    override fun send(json: String) {
        UnityPlayer.UnitySendMessage("Bridge", "OnCommand", json)
    }

    override fun pause() {
        val current = player ?: return
        current.windowFocusChanged(false)
        current.pause()
        current.onPause()
    }

    override fun resume() {
        val current = player ?: return
        current.resume()
        current.onResume()
        current.windowFocusChanged(true)
    }

    override fun attach(container: FrameLayout) {
        val view = player?.playerView() ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        container.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        resume()
    }

    override fun detach(container: FrameLayout) {
        val view = player?.playerView() ?: return
        container.removeView(view)
        pause()
    }

    override fun onHostResume() = resume()

    override fun onHostPause() = pause()

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        player?.windowFocusChanged(hasFocus)
    }
}

private fun UnityPlayerForActivityOrService.playerView(): View {
    return view as View
}
