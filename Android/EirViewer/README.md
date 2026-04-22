# Eir Viewer for Android

Native Android app scaffold for the Eir iOS viewer, built with Kotlin and Jetpack Compose.

## Current scope

- Import `.eir`, `.yaml`, or `.yml` exports from the Android file picker
- Copy imported files into app storage and persist profile metadata locally
- Parse EIR YAML into Android data models
- Browse journal history with search, category filters, provider filters, and detail view
- Keep the iOS app's high-level tab structure in place for later feature ports
- Chat flow: local thread/message persistence and OpenAI-compatible API-backed assistant chat

## Not ported yet

- Tool-calling and function actions in chat
- Health Connect import
- Find Care clinic search and maps
- Billing
- On-device local models

## Open on macOS

1. Install Android Studio on your Mac.
2. Open the `Android/EirViewer` folder as a project.
3. Let Android Studio install the Android SDK, JDK, and Gradle dependencies it prompts for.
4. Run the `app` configuration on an emulator or device.

## Notes

- This repository session did not have Java, Gradle, or Android Studio available, so the project files were created without a local build verification pass.
- The Gradle wrapper is configured separately; if Android Studio offers to regenerate or update it, that is expected.
