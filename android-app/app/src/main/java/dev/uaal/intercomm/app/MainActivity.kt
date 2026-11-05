package dev.uaal.intercomm.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.uaal.intercomm.UnityHost

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            UaalApp()
        }
    }

    override fun onResume() {
        super.onResume()
        UnityHost.shared.onHostResume()
    }

    override fun onPause() {
        UnityHost.shared.onHostPause()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        UnityHost.shared.onWindowFocusChanged(hasFocus)
    }
}
