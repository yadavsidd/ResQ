# ResQ — Offline AI Disaster Relief, Powered by Gemma 4 On-Device

**Subtitle**: When networks fail and lives are at stake, ResQ works without internet — Gemma 4 E2B runs entirely on the phone via LiteRT.

## The Problem
Natural disasters—earthquakes, severe floods, and raging wildfires—almost universally destroy cellular towers, power lines, and ISP infrastructure. In the critical first 72 hours following an event, survivors and first responders are completely cut off from the web. Yet, this is precisely when individuals desperately need accurate survival instructions, location tracking, and medical guidance. The reliance on cloud-bound APIs and traditional web searches renders modern LLM technologies utterly useless in the field when they are needed most.

## The Solution
ResQ is an uncompromising, offline-first personal emergency assistant built in Flutter for cross-platform deployment. Designed assuming zero cellular connectivity, ResQ completely localizes vital survival tools. It features a fully cached OpenStreetMap cartography engine leveraging satellite-only GPS, allowing users to navigate securely to pre-loaded community shelters or hospitals. It natively bundles a 15-topic emergency protocol dashboard, complete with dynamic TTS for terrified or injured users. 

Most importantly, ResQ is brained by Google’s highly capable Gemma 4 E2B parameter model running deeply integrated into the local hardware. By moving state-of-the-art Generative AI entirely to the mobile edge, ResQ can generate personalized, real-time survival checklists and provide interactive triage advice irrespective of grid conditions.

## How Gemma 4 is Used
We strategically selected the Gemma 4 E2B architecture for its unprecedented capability-to-size ratio, making it the perfect candidate for local mobile computing. Because ResQ targets disaster victims, we completely eliminated any cloud latency or dependency by utilizing `tflite_flutter` (LiteRT) to deploy the 1.3 GB `.tflite` model directly onto the device's CPU/GPU backend processors.

We engineered a specialized, strict system prompt enforcing the model to adopt the persona of a calm, concise responder: *"Keep responses under 150 words... respond with numbered steps. You work fully offline."* We implemented autoregressive UI streaming, rendering the tokens on-screen the millisecond they are decoded, matching the responsiveness users expect from cloud APIs.

Because disaster zones are chaotic, ResQ supports multilingual inference handling Hindi seamlessly alongside English. We built a structured parameterized ingestion form for checklists. The app feeds Gemma robust arrays outlining disaster types and vulnerable group needs, returning actionable survival lists without hallucinations. Should LiteRT fail to initialize on severely outdated, low-RAM hardware, ResQ silently falls back entirely to a massive local SQLite repository, ensuring the user is never left without life-saving heuristic answers.

## Technical Challenges & Solutions
**The 1.3GB Model Boundary:** Google Play and the App Store enforce strict binary constraints. Packaging the raw Gemma model into the APK was impossible. We built a complex first-launch Onboarding pipeline utilizing `dio` chunked streaming and SHA-256 verification. Users download the "AI Brain" once securely over home Wi-Fi into an isolated Application Documents partition.

**Memory Overflows:** Parsing the 256k Gemma vocabulary safely into a mobile tensor graph easily caused out-of-memory crashes on midrange phones targeting 4GB total constraints. We bypassed traditional garbage collection bottlenecks by structuring the `tflite_flutter` Interpreter to restrict hardware bridging precisely to 4 CPU threads and limiting the sliding context window dynamically.

**Accessibility in Panic:** When trapped in burning infrastructure or collapsed buildings, users cannot type. We integrated completely local `speech_to_text` capturing voice without GSM networks, feeding directly into the Gemma context buffer. Text scale adjustability and offline Text-to-Speech (TTS) bindings guarantee that even users suffering from smoke inhalation or debris injuries can operate ResQ entirely hands-free. Minimum touch targets are enforced rigorously throughout the UI.

## Impact & Tracks
ResQ fundamentally revolutionizes offline empowerment, hitting 4 tracks simultaneously:
* **Global Resilience:** Direct, actionable, personalized survival guidance exactly when standard internet communications fail during crisis scenarios.
* **Digital Equity:** Runs smoothly via hardware optimization on mid-range global hardware; no expensive 5G or premium server subscriptions required to access state-of-the-art AI.
* **Cactus:** Flawlessly localized First Aid rendering algorithms supporting Hindi dynamically, tailored directly for Indian subcontinent crisis scenarios. 
* **LiteRT:** A textbook showcase of pushing massive LLM parameter counts efficiently down into edge-mobile environments replacing generic cloud APIs. 

## What's Next
Community data crowdsourcing for local SQLite databases—enabling organizers to seed thousands of emergency water and food drop sites natively. We intend to adopt the impending Gemma 4 E4B models for even more reliable logical triage paths. Finally, porting the codebase onto WearOS and watchOS, providing heart-rate tracking and fully hands-free rescue integrations.
