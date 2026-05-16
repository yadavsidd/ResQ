# Deploying ResQ for Judges

To empower judges to easily access and test ResQ without needing a local development environment, follow these deployment steps to distribute the app.

## Option 1: Android APK Release (Fastest for Android Judges)

Building a release APK is the simplest way to distribute Android builds without needing a Google Play Store review.

1. **Build the APK**:
   ```bash
   flutter build apk --release
   ```
2. **Locate the APK**:
   The generated file is located at: `build/app/outputs/flutter-apk/app-release.apk`
3. **Distribute via Kaggle/GitHub**:
   Upload `app-release.apk` to a Kaggle Dataset, a GitHub Release page, or Google Drive, and provide the direct download link in your Kaggle submission.
4. **Judge Instructions**:
   Instruct the judges to download the APK directly to their Android phones, simply tap it, and accept "Install from unknown sources" if prompted.

## Option 2: Web Distribution (Fallback Demo)

*Note: The primary value of ResQ is on-device AI which requires a native shell environment (LiteRT does not run on Flutter Web). However, if you want judges to see the UI quickly without installing anything, you can deploy a lightweight web version using the Fallback logic.*

1. Add web support to the project if not enabled:
   ```bash
   flutter create . --platforms web
   ```
2. Build for the web:
   ```bash
   flutter build web
   ```
3. Deploy to GitHub Pages or Firebase Hosting:
   ```bash
   # Using Firebase Hosting
   firebase deploy --only hosting
   ```
   *Judge Instruction: Warn them that the Web version only demonstrates UI and Fallback SQL logic—true AI inference requires a mobile device.*

## Option 3: iOS TestFlight (For iOS Judges)

Deploying to iOS requires an Apple Developer account.
1. **Archive the Build**:
   Open Xcode (`xed ios`), select "Any iOS Device" as the build target.
   Go to Product > Archive.
2. **Distribute App**:
   Once archived, click "Distribute App" and upload it to App Store Connect.
3. **TestFlight**:
   Add the judges' Apple ID emails to your Internal Testers list in App Store Connect, or generate a Public TestFlight Link to include in your Kaggle submission.

## Post-Installation Recommendations for Judges
Include a note in your submission:
> "Once installed, open ResQ. You can elect to download the 1.3GB AI model, or immediately press **Skip Download (Demo Mode)** to jump directly into the app and test our offline caching and SQLite features immediately."
