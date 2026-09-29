package com.lemercier.scantickets

import android.graphics.Bitmap
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lemercier.scantickets.ui.EditorDialog
import com.lemercier.scantickets.ui.ExportScreen
import com.lemercier.scantickets.ui.ListScreen
import com.lemercier.scantickets.ui.ScanScreen
import com.lemercier.scantickets.ui.ScanTicketsTheme
import com.lemercier.scantickets.ui.SettingsScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ScanTicketsTheme { App() }
        }
    }
}

/** Ouverture de la fiche d'un ticket */
data class EditorRequest(
    val ticket: Ticket,
    val image: Bitmap?,
    val isNew: Boolean,
    val autoAnalyze: Boolean,
)

@Composable
fun App(store: TicketStore = viewModel()) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var editor by remember { mutableStateOf<EditorRequest?>(null) }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0, onClick = { tab = 0 }, label = { Text("Tickets") },
                    icon = {
                        BadgedBox(badge = { if (store.toReviewCount > 0) Badge { Text("${store.toReviewCount}") } }) {
                            Icon(Icons.Filled.ReceiptLong, null)
                        }
                    },
                )
                NavigationBarItem(selected = tab == 1, onClick = { tab = 1 }, label = { Text("Scanner") },
                    icon = { Icon(Icons.Filled.DocumentScanner, null) })
                NavigationBarItem(selected = tab == 2, onClick = { tab = 2 }, label = { Text("Export") },
                    icon = { Icon(Icons.Filled.TableChart, null) })
                NavigationBarItem(selected = tab == 3, onClick = { tab = 3 }, label = { Text("Réglages") },
                    icon = { Icon(Icons.Filled.Settings, null) })
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (tab) {
                0 -> ListScreen(
                    store,
                    onOpen = { t -> editor = EditorRequest(t, store.loadBitmap(t), isNew = false, autoAnalyze = false) },
                    onScan = { tab = 1 },
                )
                1 -> ScanScreen(store, onEdit = { editor = it }, onDone = { tab = 0 })
                2 -> ExportScreen(store)
                else -> SettingsScreen(store)
            }
        }
    }

    store.batchMessage?.let { msg ->
        AlertDialog(
            onDismissRequest = { store.batchMessage = null },
            text = { Text(msg) },
            confirmButton = { TextButton(onClick = { store.batchMessage = null }) { Text("OK") } },
        )
    }

    editor?.let { req ->
        EditorDialog(store, req) { saved ->
            editor = null
            if (saved && req.isNew) tab = 0
        }
    }
}
