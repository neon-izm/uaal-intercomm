package dev.uaal.intercomm

import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

@Composable
fun UnityView(modifier: Modifier = Modifier) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            FrameLayout(context).also { frame ->
                frame.setBackgroundColor(android.graphics.Color.BLACK)
                UnityHost.shared.attach(frame)
            }
        },
        onRelease = { frame ->
            UnityHost.shared.detach(frame)
        },
    )
}
