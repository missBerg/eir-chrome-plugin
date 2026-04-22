package com.eir.viewer.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import com.eir.viewer.android.ui.EirApp
import com.eir.viewer.android.ui.MainViewModel
import com.eir.viewer.android.ui.theme.EirTheme

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            EirTheme {
                EirApp(viewModel = viewModel)
            }
        }
    }
}
