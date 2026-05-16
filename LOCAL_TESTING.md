# Testing ResQ Locally

This guide will walk you through building and testing the ResQ Flutter application on your local machine, simulator, or physical smartphone.

## Prerequisites

Before testing, ensure your local development environment is set up:
1. **Flutter SDK**: Ensure you have Flutter version 3.3.0 or higher installed. Run `flutter doctor` to verify your environment.
2. **Platform Tools**: 
   - For Android: Android Studio with the Android SDK installed.
   - For iOS: Xcode installed (requires a Mac).

## Running on an Emulator or Simulator

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/ResQ/resq
   cd resq
   ```
2. **Install Dependencies**:
   ```bash
   flutter pub get
   ```
3. **Start an Emulator/Simulator**:
   Open Android Studio's Virtual Device Manager and start an Android emulator, or open Simulator on macOS for iOS testing.
4. **Run the App**:
   ```bash
   flutter run
   ```
   *Note: Using an emulator might not fully demonstrate the performance of the on-device Gemma LiteRT model due to lack of direct hardware acceleration, but it will work for the fallback logic.*

## Running on a Physical Smartphone (Recommended)

Testing on a real device is highly recommended to experience the true offline performance and hardware acceleration of the Gemma 4 E2B model.

### Android
1. Enable **Developer Options** and **USB Debugging** on your phone.
2. Connect your phone to your computer via USB.
3. Verify your device is detected:
   ```bash
   flutter devices
   ```
4. Build and install an APK:
   ```bash
   flutter run --release
   ```
   *(Running in release mode optimizes the C++ bindings for the LiteRT AI model, resulting in significantly faster generation times).*

### iOS
1. Open the iOS project in Xcode:
   ```bash
   cd ios
   pod install
   xed .
   ```
2. Connect your iPhone to your Mac.
3. In Xcode, select your iPhone as the run destination. Set up your Apple Developer Team in the "Signing & Capabilities" tab.
4. Build and run from Xcode, or from the terminal:
   ```bash
   flutter run --release
   ```

## The 1.3 GB Model Download

On the first launch, ResQ will prompt you to download the "AI Brain" (Gemma 4 TFLite model).
- Ensure you have a strong Wi-Fi connection for this step.
- If you are testing the app's structural flow and do not wish to wait for the download, click the **Skip Download (Demo Mode)** button. The app will immediately fall back to its offline SQLite capabilities.
