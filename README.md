# ResQ — Offline Disaster Relief Assistant

**Kaggle Gemma 4 Good Hackathon Submission**  
_Tracks: Global Resilience | Digital Equity | Cactus | LiteRT_

ResQ is an offline-first disaster relief assistant built for iOS and Android. When earthquakes, floods, and wildfires destroy cell towers and internet infrastructure, ResQ functions entirely isolated on local hardware to guide survivors, first responders, and volunteers to safety.

## What ResQ Does
* **100% Offline AI Chat**: A local intelligent assistant powered by Google Gemma that answers critical survival questions without a cellular connection.
* **Dynamic Offline Maps**: Pre-cached OpenStreetMap tiles and 10+ embedded SQLite safety markers providing GPS-based survival routing.
* **AI Checklist Generator**: Personalised evacuation and supply checklists dynamically compiled on-device based on group size, vulnerable individual status, and disaster classification.
* **Emergency First Aid Guide**: A fast library of 15 vital survival topics structured with keyword accessibility emojis and embedded Text-to-Speech (TTS) for panicked users, functioning locally in English and Hindi.

## How Gemma 4 E2B Powers ResQ (LiteRT)
ResQ runs the massive **1.3 GB Gemma 4 E2B** parameter model fully on your device CPU/GPU utilizing Google AI Edge LiteRT (`tflite_flutter`). 
There are ZERO server-side API calls.

1. **LiteRT Integration:** We natively encode standard token IDs bypassing `google_generative_ai` networked paths and directly bind to the underlying local hardware tensor array.
2. **Onboarding Pipeline:** The 1.3 GB model is too computationally dense for an App Store binary. ResQ features a first-launch Model Downloader streaming bytes natively from a CDN into the isolated App Documents Directory, complete with SHA-256 safety checks constraints.
3. **Graceful Fallbacks:** If the device has insufficient RAM, architecture mismatches, or hasn't finished the download, ResQ gracefully jumps out of LiteRT initialization and fails over to a hardened SQLite DB filled with pre-computed heuristic Q&A pairs to guarantee the user is never left without critical guidance.

## Architecture

```text
┌────────────────────────────────────────────────────────┐
│ ResQ Flutter Application                               │
│                                                        │
│  ┌───────────────┐  ┌───────────────┐  ┌────────────┐  │
│  │ Chat Assistant│  │ Map Cache (DB)│  │ First Aid  │  │
│  └───────┬───────┘  └───────┬───────┘  └──────┬─────┘  │
└──────────┼──────────────────┼─────────────────┼────────┘
           │                  │                 │
┌──────────▼──────────────────▼─────────────────▼────────┐
│ Service Layer (AppState / SharedPrefs)                 │
└─┬──────────────────────┬────────────────────────────┬──┘
  │                      │                            │
┌─▼─────────────┐ ┌──────▼────────┐           ┌───────▼───────┐
│ GemmaService  │ │ SQLite (Local)│           │ Geolocation   │
│ (LiteRT)      │ │ Fallback Q&A  │           │ Offline Maps  │
└───────────────┘ └───────────────┘           └───────────────┘
  [gemma-4.tflite] (1.3 GB Local Disk)
```

## How to Build

### Prerequisites
- Flutter SDK `>=3.3.0`
- Android Studio / Xcode

```bash
# 1. Clone the repo
git clone https://github.com/ResQ/resq
cd resq

# 2. Get dependencies
flutter pub get

# 3. Build the app
flutter build apk --release
# OR
flutter build ios --release
```

## Where to get the Gemma 4 E2B TFLite model file
During standard operation, the ResQ application downloads the model automatically from Google's Cloud Storage URLs upon first launch into the shielded application environment. 
If developers wish to seed this manually or test inference pipelines:
1. Download `gemma-4-e2b.tflite` from Kaggle Models or Google AI Edge.
2. Build the app and run it in an emulator once.
3. Push the model via `adb` or Xcode Devices window directly into the Documents directory:  
   `/data/user/0/com.example.resq/app_flutter/gemma-4-e2b.tflite`

## Instructions for Judges (Demo Mode)
If you wish to test ResQ but don't want to wait for the 1.3 GB download on the simulator:
1. Open the application. Upon reaching the "Download AI Brain" onboarding screen, select the **Skip Download (Demo Mode)** button.
2. The app will boot into **Offline Fallback Mode**. You will see the AI status banner immediately flag itself as **Orange** (`AI Offline — Using Cached Responses`). 
3. You can now natively test our strict Fallback Checklist Generator, custom SOS emergency Maps engine, and SQLite heuristic Chat engine!
4. Swipe over to the **First Aid Guide Screen** and note how high-priority protocols jump to the top, and UI emojis assemble dynamically across both English & Hindi formats without breaking Text-to-Speech strings!
