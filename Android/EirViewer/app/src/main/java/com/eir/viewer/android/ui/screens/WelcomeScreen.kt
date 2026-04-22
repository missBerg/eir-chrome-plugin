package com.eir.viewer.android.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import com.eir.viewer.android.ui.theme.Primary
import com.eir.viewer.android.ui.theme.TextSecondary
import androidx.compose.foundation.shape.RoundedCornerShape

@Composable
fun WelcomeScreen(
    isLoading: Boolean,
    onChooseFile: () -> Unit,
    onLoadSample: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
            shape = RoundedCornerShape(24.dp),
        ) {
            Column(
                modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(76.dp)
                        .background(Primary.copy(alpha = 0.14f), shape = RoundedCornerShape(38.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Home,
                        contentDescription = null,
                        tint = Primary,
                        modifier = Modifier.size(38.dp),
                    )
                }
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Eir Viewer",
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = "Your Swedish health records, made easy on Android",
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 8.dp),
                    color = TextSecondary,
                )
                Spacer(modifier = Modifier.height(6.dp))
                HorizontalDivider(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 14.dp, bottom = 14.dp),
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                )
                Text(
                    text = "Start with your .eir export or load sample data to explore records, actions, and care guidance.",
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    color = TextSecondary,
                )
            }
        }

        Spacer(modifier = Modifier.height(22.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Button(
                onClick = onChooseFile,
                modifier = Modifier.weight(1f),
                enabled = !isLoading,
            ) {
                Text("Choose .eir file")
            }
            OutlinedButton(
                onClick = onLoadSample,
                modifier = Modifier.weight(1f),
                enabled = !isLoading,
            ) {
                Text("Try sample data")
            }
        }

        if (isLoading) {
            Spacer(modifier = Modifier.height(24.dp))
            CircularProgressIndicator(color = Primary)
        }
    }
}
