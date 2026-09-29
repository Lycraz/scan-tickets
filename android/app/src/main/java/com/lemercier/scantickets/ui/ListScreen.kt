package com.lemercier.scantickets.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.lemercier.scantickets.Fmt
import com.lemercier.scantickets.Ticket
import com.lemercier.scantickets.TicketStore
import java.time.LocalDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListScreen(store: TicketStore, onOpen: (Ticket) -> Unit, onScan: () -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    val tickets = store.tickets
    val q = search.trim().lowercase()
    val filtered = if (q.isEmpty()) tickets else tickets.filter {
        listOf(it.commercant, it.nature, it.description, it.notes, it.paiement, it.affaire, it.lieu)
            .joinToString(" ").lowercase().contains(q)
    }
    val sections = filtered.groupBy { it.monthKey }.toSortedMap(compareByDescending { it })
    val currentMonth = Fmt.monthKey(LocalDate.now())
    val monthTotal = tickets.filter { it.monthKey == currentMonth }.sumOf { it.ttc ?: 0.0 }

    Scaffold(topBar = { TopAppBar(title = { Text("Mes tickets", fontWeight = FontWeight.Bold) }) }) { padding ->
        if (tickets.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Filled.DocumentScanner, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(12.dp))
                Text("Aucun ticket", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Scannez votre premier ticket : l'app lit le montant, la date et le commerçant.",
                    textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
                Button(onClick = onScan) { Text("Scanner un ticket") }
            }
            return@Scaffold
        }
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        ) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(
                        Modifier.weight(1.4f).clip(RoundedCornerShape(16.dp))
                            .background(Brush.linearGradient(listOf(Color(0xFF6366F1), Color(0xFF4338CA))))
                            .padding(16.dp),
                    ) {
                        Text("Ce mois-ci", color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.labelMedium)
                        Text(Fmt.money(monthTotal), color = Color.White, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    }
                    Card(Modifier.weight(1f), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                        Column(Modifier.padding(16.dp)) {
                            Text("Tickets", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text("${tickets.size}", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                            if (store.toReviewCount > 0) Text("${store.toReviewCount} à vérifier", color = Warning, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
            item {
                OutlinedTextField(
                    value = search, onValueChange = { search = it },
                    placeholder = { Text("Commerçant, nature, affaire…") },
                    leadingIcon = { Icon(Icons.Filled.Search, null) },
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                )
            }
            sections.forEach { (month, list) ->
                item(key = "h$month") {
                    Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 8.dp, bottom = 6.dp)) {
                        Text(Fmt.monthTitle(month).uppercase(), style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                        Text(Fmt.money(list.sumOf { it.ttc ?: 0.0 }), style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                items(list, key = { it.id }) { t -> TicketRow(store, t) { onOpen(t) } }
            }
            if (filtered.isEmpty()) item { Text("Aucun résultat.", Modifier.padding(24.dp)) }
        }
    }
}

@Composable
fun TicketRow(store: TicketStore, t: Ticket, onClick: () -> Unit) {
    val thumb = remember(t.id, t.createdAt) { store.thumbnail(t) }
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
    ) {
        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(48.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                if (thumb != null) {
                    Image(thumb.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                } else {
                    Icon(if (t.isKilometres) Icons.Filled.DirectionsCar else Icons.Filled.Receipt, null,
                        tint = MaterialTheme.colorScheme.primary)
                }
            }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                val title = if (t.isKilometres) t.description.ifBlank { "Trajet en voiture" }
                else t.commercant.ifBlank { "Sans nom" }
                Text(title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(Fmt.shortDay(t.date), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Chip(t.nature, MaterialTheme.colorScheme.primary)
                    if (t.aVerifier) Chip("à vérifier", Warning)
                }
            }
            Text(
                if (t.isKilometres) "${Fmt.kmString(t.km)} km" else Fmt.money(t.ttc, t.devise),
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun Chip(text: String, color: Color) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = color,
        modifier = Modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 2.dp),
    )
}
