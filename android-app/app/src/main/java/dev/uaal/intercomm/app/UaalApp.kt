package dev.uaal.intercomm.app

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import dev.uaal.intercomm.PrefabId
import dev.uaal.intercomm.UnityHost
import dev.uaal.intercomm.UnityHostError
import dev.uaal.intercomm.UnityView
import kotlinx.coroutines.launch

@Composable
fun UaalApp() {
    MaterialTheme {
        val nav = rememberNavController()
        NavHost(navController = nav, startDestination = "home") {
            composable("home") {
                HomeScreen(onOpen = { nav.navigate("car") })
            }
            composable("car") {
                CarScreen(onBack = { nav.popBackStack() })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(onOpen: () -> Unit) {
    val activity = LocalContext.current as ComponentActivity
    var status by remember { mutableStateOf("起動しています") }
    var ready by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        try {
            status = "起動しています"
            UnityHost.shared.initialize(activity)
            UnityHost.shared.load()
            UnityHost.shared.keepOffscreen()
            ready = true
            status = "準備できました"
        } catch (error: Throwable) {
            status = message(error)
        }
    }

    Scaffold(topBar = { TopAppBar(title = { Text("uaal-intercomm") }) }) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(status, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(
                onClick = onOpen,
                enabled = ready,
                modifier = Modifier.padding(top = 24.dp),
            ) {
                Text("車を見る")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CarScreen(onBack: () -> Unit) {
    var status by remember { mutableStateOf("車を選んでください") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Scaffold(topBar = { TopAppBar(title = { Text("車") }) }) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            UnityView(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(520.dp),
            )
            Text(status, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PrefabId.entries.forEach { id ->
                    Button(
                        onClick = {
                            scope.launch {
                                busy = true
                                status = "${title(id)}を読み込んでいます"
                                try {
                                    UnityHost.shared.loadPrefab(id)
                                    status = "${title(id)}を表示しました"
                                } catch (error: Throwable) {
                                    status = message(error)
                                }
                                busy = false
                            }
                        },
                        enabled = !busy,
                    ) {
                        Text(title(id))
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                colorButtons.forEach { color ->
                    Button(
                        onClick = {
                            try {
                                UnityHost.shared.setColor(color.r, color.g, color.b)
                                status = "色を変えました"
                            } catch (error: Throwable) {
                                status = message(error)
                            }
                        },
                        enabled = !busy,
                    ) {
                        Text(color.name)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(1 to "正面", 2 to "側面", 3 to "上面").forEach { (index, label) ->
                    Button(
                        onClick = {
                            try {
                                UnityHost.shared.setCamera(index)
                                status = "${label}に切り替えました"
                            } catch (error: Throwable) {
                                status = message(error)
                            }
                        },
                        enabled = !busy,
                    ) {
                        Text(label)
                    }
                }
            }
            Button(onClick = onBack) {
                Text("戻る")
            }
        }
    }
}

private data class ColorChoice(val name: String, val r: Float, val g: Float, val b: Float)

private val colorButtons = listOf(
    ColorChoice("白", 1f, 1f, 1f),
    ColorChoice("赤", 0.8f, 0.1f, 0.1f),
    ColorChoice("青", 0.15f, 0.35f, 0.9f),
    ColorChoice("黒", 0.08f, 0.08f, 0.08f),
)

private fun title(id: PrefabId): String {
    return when (id) {
        PrefabId.carA -> "セダン"
        PrefabId.carB -> "SUV"
        PrefabId.carC -> "レース"
    }
}

private fun message(error: Throwable): String {
    return when (error) {
        is UnityHostError -> error.message ?: error.toString()
        else -> error.message ?: error.toString()
    }
}
