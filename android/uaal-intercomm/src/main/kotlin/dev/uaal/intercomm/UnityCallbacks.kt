package dev.uaal.intercomm

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CountDownLatch

object UnityCallbacks {
    @JvmStatic
    fun onBridgeEvent(json: String?) {
        val text = json.orEmpty()
        if (Looper.myLooper() == Looper.getMainLooper()) {
            UnityHost.shared.handle(text)
            return
        }
        val done = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            UnityHost.shared.handle(text)
            done.countDown()
        }
        done.await()
    }
}
