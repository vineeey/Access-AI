# AccessAI — AI-Powered Smart Accessibility Doorbell for Blind & Deaf People
### Detailed Project Note

---

## 1. Abstract

AccessAI is an intelligent doorbell system designed to restore independence, safety, and dignity to people who are blind or deaf when someone arrives at their door. An ordinary doorbell communicates a single fact — *"somebody is here"* — through a sound. For a deaf person that sound is inaccessible; for a blind person it carries no information about *who* is outside or *why* they have come. This forces a daily choice between dependence on others and the risk of opening the door to an unknown person.

AccessAI replaces the meaningless chime with **meaning**. Using a small camera at the door and an AI processing unit (a laptop during development, an embedded ESP32-CAM in the deployed version), the system recognises known visitors by their face, understands the scene using a vision model, reads out any carried objects such as parcels, transcribes what the visitor says, and fuses all of this into a single clear message. That message is delivered through a **Blind Mode** (spoken announcements and vibration) and a **Deaf Mode** (large on-screen text, live captions, visual and vibration alerts, and two-way text-to-speech communication). The result transforms a door chime into a sentence such as: *"Rahul is at the front door. He is carrying a parcel. He said, 'Package for you.'"*

The system is built almost entirely from proven, free, open-source AI components running locally, which keeps the cost under ₹5,000 for a working prototype and — critically — keeps all image and audio data inside the home for privacy. AccessAI's novelty is not any single model but the **accessibility-first integration** of several models into a coherent assistant purpose-built for users that mainstream smart doorbells ignore.

---

## 2. Introduction and Background

Doorbells are among the oldest pieces of home technology, and their fundamental design has barely changed in a century. A button outside triggers a chime inside. This works well for the general population but embeds two hidden assumptions: that the occupant can **hear** the chime, and that the occupant can safely **see** who is at the door before deciding to open it. For millions of people with visual or hearing impairment, one or both of these assumptions fail.

Recent years have brought "smart doorbells" — internet-connected devices with cameras that stream video to a smartphone and, in premium versions, recognise faces or detect packages. Products such as Ring, Google Nest, and Amazon's ecosystem have made video doorbells mainstream. However, these devices are designed for sighted, hearing users. Their entire interaction model assumes the user will look at a video feed on a screen and read or listen to alerts. They optimise for **security and convenience**, not **accessibility**. A blind user cannot benefit from a video feed; a deaf user cannot benefit from an audio-based interaction with the visitor.

At the same time, artificial intelligence has matured to a point where a machine can genuinely *understand* an image and describe it in words, recognise a specific person, transcribe speech, and speak naturally — all on affordable, local hardware. This convergence creates an opportunity: to build a doorbell whose primary job is not to record video for a sighted owner, but to **translate the world outside the door into a form that a blind or deaf person can perceive**. AccessAI is that doorbell.

---

## 3. Problem Statement

Answering the door is a routine task that most people never think about. For people with sensory disabilities, it is a recurring source of anxiety, dependence, and even danger.

**For a blind person**, the doorbell rings but conveys nothing about the identity or intent of the visitor. They cannot distinguish a family member from a stranger, a trusted delivery agent from an unknown caller, or a friend from someone with harmful intent. Their options are limited: open the door blindly and accept the risk, call out and hope the visitor answers honestly, or ignore the door entirely and miss important visitors and deliveries. Each option trades away either safety or independence.

**For a deaf person**, the problem begins earlier — they may not perceive the doorbell at all. Even if a visual alert exists, once they reach the door they cannot hear what the visitor is saying, and the visitor cannot easily understand them. Deliveries are missed, guests are left waiting, and ordinary interactions become stressful. Communication across the closed door — a normal exchange like "leave it at the gate" — is effectively impossible.

**The core problem**, therefore, is that the doorbell as it exists communicates through exactly the sensory channels these users lack, and provides none of the contextual information (who, what, why) that would let them respond safely and independently. Existing smart doorbells do not solve this because they simply shift the same visual-and-audio interaction onto a smartphone screen, again assuming the user can see and hear. **There is no affordable, accessibility-first doorbell that perceives the visitor on the user's behalf and communicates that understanding through the sense the user actually has.**

---

## 4. Motivation

The motivation for AccessAI is both social and technical.

Socially, accessibility technology is one of the most meaningful applications of engineering: it directly returns autonomy to people who have been excluded by mainstream design. The population of people who are blind or have low vision, and those who are deaf or hard of hearing, numbers in the tens of millions in India alone and far more globally. Yet consumer technology rarely treats them as a primary audience. A project that centres them is both morally worthwhile and commercially under-served.

Technically, the project is motivated by the fact that the individual AI capabilities required — face recognition, scene understanding, speech recognition, and speech synthesis — are now mature, open-source, and runnable on modest hardware. The intellectual challenge and contribution lie not in inventing a new model but in **orchestrating** these capabilities into a reliable, low-latency, privacy-preserving system with an interface genuinely usable by blind and deaf users. This is exactly the kind of applied, integrative, real-world problem that an AI and Data Science final-year project should tackle: it exercises computer vision, audio processing, data fusion, edge deployment, and human-centred design, while solving a problem that matters.

---

## 5. Aim and Objectives

**Aim:** To design and build an AI-powered smart doorbell that perceives and interprets visitors on behalf of blind and deaf users and communicates that information through accessible output channels.

**Objectives:**

1. To capture a visitor's image (and, on request, audio) at the moment of a doorbell press or motion event.
2. To recognise known household members and label them by name using facial embeddings.
3. To understand unknown visitors by detecting carried objects and generating a natural-language description of the scene.
4. To infer the *likely* purpose of the visit (delivery, guest, service worker, unknown) from the fused evidence, without overstating certainty.
5. To transcribe what the visitor says and, where needed, translate it into the user's language.
6. To deliver all of this through a **Blind Mode** (spoken announcement plus vibration) and a **Deaf Mode** (visual text, captions, vibration, and two-way text-to-speech communication).
7. To maintain a searchable **visitor history** with snapshots and summaries.
8. To keep processing **local and private**, and total prototype cost **under ₹5,000**.
9. To design the software so that the same code runs first on a laptop webcam and later on an embedded ESP32-CAM with only a configuration change.

---

## 6. Scope

**In scope.** A single front-door unit; recognition of a household's registered faces; detection of common visitor-related objects (bags, parcels, documents, tools, and similar); a natural-language scene description; rule-and-context-based intent inference; a Blind Mode and a Deaf Mode; on-demand two-way text communication; local storage of visitor events; and a development path from laptop webcam to embedded camera.

**Out of scope (stated honestly).** The system does not claim to determine a stranger's *true* intentions — it reports only what is visibly likely. It does not perform medical-grade identification, does not guarantee accuracy in very poor lighting, and in its prototype form is not hardened for outdoor weather or certified for commercial sale. Continuous 24×7 video analytics, multi-building scaling, and night-vision-grade performance are treated as future work rather than core deliverables. Being explicit about these boundaries is itself part of good engineering: the system is designed to be honest about its uncertainty.

---

## 7. Existing Systems and the Gap

Several categories of related product exist, and understanding them clarifies exactly where AccessAI's contribution lies.

**Mainstream smart video doorbells** (Ring, Google Nest, Amazon) provide a camera, motion alerts, cloud recording, and — in premium tiers — face recognition and package detection. They are excellent for security-conscious, sighted, hearing homeowners. Their limitations for our users are fundamental, not incidental: the interaction is built around a video feed on a screen and text or audio notifications, precisely the channels a blind or deaf person cannot use. They also depend on the cloud and paid subscriptions, and route private footage through external servers.

**Assistive apps for the blind** (for example, apps that read text aloud or describe a scene from a phone camera) demonstrate that AI scene description is feasible, but they are general-purpose and not integrated into the doorbell context, nor do they combine identity, objects, and speech into a single doorstep event.

**Deaf-notification systems** (flashing-light doorbells, vibration alerts) solve the *awareness* problem — that someone is at the door — but do nothing for the *communication* problem once the user reaches the door.

The **gap**, therefore, is a system that (a) treats blind and deaf users as the primary audience, (b) fuses face, object, scene, and speech into one contextual understanding, (c) offers two-way doorstep communication for the deaf, and (d) runs locally for privacy without a subscription. No mainstream product occupies this space. AccessAI's contribution is this integration and reframing, built from proven components — which is a legitimate and defensible innovation for a student project and a genuine market opening for a product.

---

## 8. Proposed System — Overview

AccessAI is organised as three cooperating tiers.

The **Doorbell Unit** sits at the door. During development this is simply the laptop's webcam; in deployment it is an ESP32-CAM with a button, an LED, and optionally a microphone and motion sensor. Its only responsibilities are to *detect* a trigger, *capture* an image (and optional audio), and *transmit* the data. It is deliberately kept simple so that all intelligence lives elsewhere.

The **AI Processing Server** is the brain. During development this is the student's laptop; in a product it could be a small always-on device such as an NVIDIA Jetson, a Raspberry Pi 5, or a cloud endpoint. It runs the face recognition, the vision model, the speech recognition, the context/fusion engine, and the accessibility response engine. It exposes an API that the doorbell and the app talk to.

The **User Interface** is a mobile application (and, during development, the laptop console and screen). It presents notifications, the live camera view, the visitor history, accessibility settings, and the two-way communication screen. It switches its entire behaviour based on whether the user has selected Blind Mode or Deaf Mode.

The flow between them is: *trigger → capture → transmit → analyse → fuse → deliver → store → return to idle*.

---

## 9. System Architecture in Detail

```
        VISITOR
          │  (presses button / motion)
          ▼
   ┌─────────────────────┐
   │  DOORBELL UNIT       │  ESP32-CAM (or laptop webcam now)
   │  camera, button,     │
   │  LED, mic, PIR       │
   └──────────┬──────────┘
              │  Event Packet (image + audio + metadata)
        ══════╪══════  Home Wi-Fi
              ▼
   ┌──────────────────────────────────────────────┐
   │  AI PROCESSING SERVER (laptop / edge box)     │
   │  ┌────────────┐  ┌──────────────┐             │
   │  │ Face        │  │ Vision /      │            │
   │  │ Recognition │  │ Scene model   │            │
   │  └─────┬──────┘  └──────┬───────┘             │
   │        │                │                      │
   │  ┌─────▼────────────────▼──────┐  ┌──────────┐ │
   │  │      CONTEXT ENGINE          │◄─│ Speech   │ │
   │  │  (fuses all signals into     │  │ (Whisper)│ │
   │  │   one Visitor Event)         │  └──────────┘ │
   │  └───────────────┬─────────────┘                │
   │                  ▼                               │
   │        ACCESSIBILITY RESPONSE ENGINE            │
   └──────────┬──────────────────────┬──────────────┘
              ▼                       ▼
        BLIND MODE                DEAF MODE
     voice + vibration      text + captions + 2-way chat
              │                       │
              └───────────┬───────────┘
                          ▼
                 VISITOR HISTORY (database)
```

Each block is a replaceable module with a clear input and output, which makes the system easy to test piece by piece and easy to upgrade (for example, swapping a lightweight vision model for a more powerful one later without touching any other part).

---

## 10. Module-by-Module Description

**10.1 Doorbell Unit / Camera.** Captures frames. The software wraps the camera behind a single abstraction so that a webcam (`source = 0`) and an ESP32-CAM MJPEG stream (`source = "http://<ip>:81/stream"`) are interchangeable with a one-line configuration change. This is what makes the "build on laptop now, move to ESP32 later" plan practical rather than a rewrite.

**10.2 Face Recognition.** Detects faces in the captured frame, converts each into a 128-dimensional embedding, and compares it against a stored database of the household's known faces using a distance threshold. If the closest known face is within tolerance, the visitor is labelled with that person's name and a confidence score; otherwise the visitor is "Unknown." Only the mathematical embeddings are stored, not the original photographs, which is a privacy safeguard. Face recognition is kept deliberately separate from the scene model because a dedicated embedding model is far more reliable at answering "who is this" than a general vision-language model.

**10.3 Vision / Scene Understanding.** For unknown visitors especially, the system needs to understand *what* is happening. Two approaches are supported. The lighter approach uses an object detector (YOLOv8) to identify people and carried items such as bags, parcels, documents, and tools. The richer approach uses a compact vision-language model (such as Moondream or SmolVLM) that looks at the image and returns a structured JSON description: visitor count, clothing, carried objects, activity, posture, a scene summary, any hazards, and a confidence value. The JSON-only output makes the result easy for the rest of the system to consume reliably.

**10.4 Speech Recognition.** When the visitor speaks, a short audio clip is transcribed to text using an offline speech-to-text model (Whisper). A Voice Activity Detector runs first so that transcription only happens when someone is actually talking, saving computation and improving accuracy. The transcript becomes part of the visitor event and drives the Deaf Mode conversation.

**10.5 Context Engine.** This is the intelligence that turns separate signals into a single coherent understanding. It takes the face result, the vision description, the speech transcript, the time of day, and the visitor history, and produces one **Visitor Event** with a *likely* intent. Its logic is deliberately conservative — it says "likely a delivery," never "this is definitely a delivery" — because honesty about uncertainty is essential for a system that users will trust with their safety.

**10.6 Accessibility Response Engine.** This module renders the Visitor Event into the user's chosen modality. In Blind Mode it composes a natural sentence and speaks it via text-to-speech while the phone vibrates. In Deaf Mode it produces a large-text notification with the snapshot, opens the live camera, shows live captions of the visitor's speech, and enables the two-way text conversation.

**10.7 Database / Visitor History.** Every event is stored with its timestamp, identity, scene description, transcript, and snapshot, giving the user a reviewable log ("who came today"). This also enables future features such as recognising repeat unknown visitors.

**10.8 Mobile Application.** The user-facing surface: home dashboard, live camera, notifications, visitor history, communication screen, accessibility settings, and emergency alerts, with distinct Blind and Deaf interaction modes.

---

## 11. The Visitor Event — the System's Backbone

The whole system is unified by a single data object, the **Visitor Event**. Every AI module writes into it, and every output reads from it. Structuring the project around this object keeps the design clean and makes each module independently testable. A representative event looks like this:

```json
{
  "event_id": "evt_20260709_1432",
  "timestamp": "2026-07-09T14:32:10",
  "trigger": "doorbell",
  "identity": { "known": true, "name": "Rahul", "confidence": 0.97 },
  "visitor_count": 1,
  "carried_objects": ["a parcel"],
  "scene_summary": "a man in a casual shirt holding a package",
  "hazards": "none",
  "speech_transcript": "Package for you",
  "intent": "known visitor",
  "snapshot_path": "data/history/evt_20260709_1432.jpg",
  "confidence": 0.9
}
```

Blind Mode reads this and speaks a sentence; Deaf Mode reads it and renders a card; the database simply stores the whole object. Because the data model is explicit and shared, adding a new advanced feature usually means "add a field and have one module fill it in," rather than reworking the pipeline.

---

## 12. Complete Workflow

A full cycle proceeds as follows. A visitor approaches and either presses the button or is detected by the motion sensor. The camera wakes and captures two or three images; if the button was pressed, a short audio clip is also recorded so the visitor can speak a message. These are packaged into an Event Packet and sent over Wi-Fi to the AI server. The server runs face recognition on the image; if a known face is found, the identity is set. In parallel, the vision model analyses the scene and returns its structured description, and — if audio is present — the speech module transcribes it. The Context Engine fuses identity, scene, and speech into one Visitor Event and infers the likely intent. The Accessibility Response Engine then delivers the event: in Blind Mode it speaks the composed sentence and vibrates the phone; in Deaf Mode it pushes a large-text notification with the snapshot and offers the live camera and two-way chat. The event is saved to the visitor history, and the system returns to idle to await the next visitor.

---

## 13. Blind Mode and Deaf Mode in Detail

**Blind Mode** is built around sound and touch. When an event arrives, the phone (or a home speaker) first vibrates to draw attention, then speaks a complete, natural sentence assembled from the event — for example, *"Rahul is at the front door. He is carrying a parcel. He said, 'Package for you.' He has been waiting for fifteen seconds."* The user can respond hands-free using voice commands such as "who is at the door" or "open the live camera," making the entire experience usable without sight.

**Deaf Mode** is built around vision and vibration. An event triggers a strong vibration and, if configured, a screen flash, followed by a large-text notification showing the visitor's name (or "Unknown"), the carried objects, and the visitor's transcribed words. Opening the notification starts the live camera. Crucially, Deaf Mode enables **two-way communication at the door**: the visitor's speech is converted to text on the user's screen, and anything the user types is converted to speech played through a speaker at the door. This closes the communication loop that ordinary doorbells leave open for deaf users.

---

## 14. Two-Way Communication Workflow

The communication feature works as a simple, robust loop. The visitor presses the bell and speaks; the audio is transcribed and appears as text on the user's phone (for example, "Hello, I have a package"). The user types a reply ("Please leave it near the gate"); the reply is converted to speech and played at the door so the visitor hears it. This turns a one-way alert into a genuine conversation and is especially transformative for deaf users, who otherwise have no practical way to converse with someone outside a closed door. In the deployed hardware, the audio side of this loop is best handled by the phone during the live session rather than by the low-powered ESP32, keeping the door unit simple and the audio quality high.

---

## 15. Advanced AI Features (Roadmap)

Beyond the core system, AccessAI is designed to grow. Planned advanced features, in rough order of value-per-effort, include:

- **Face anti-spoofing / liveness** — verifying that a recognised face is a real, present person rather than a held-up photograph, which is essential before trusting a "known person" announcement for security.
- **Multi-language announcement and translation** — announcing in the user's preferred language and translating a visitor who speaks another language, particularly valuable in multilingual regions.
- **OCR on labels and IDs** — reading a courier company name or parcel label to enrich the announcement ("a BlueDart delivery").
- **Auto-enrollment** — clustering repeatedly-seen unknown faces so the system can suggest adding frequent visitors automatically.
- **Visitor re-identification** — noticing that the same unknown person has appeared several times, a useful safety signal.
- **Wake-word and voice commands** — hands-free control for blind users.
- **Loitering and behaviour analysis** — flagging someone who waits or paces for an unusually long time (this requires continuous frames and heavier compute, so it is later-stage work).
- **Speech emotion / urgency cues** — flagging a visitor who sounds distressed, framed cautiously as "possible urgency" because such classification is inherently uncertain.

The build order matters: anti-spoofing and multi-language give the greatest credibility for the least effort and should come first; loitering and emotion detection are deferred because they are heavier and less reliable.

---

## 16. Technology Stack

The project uses a coherent, mostly open-source stack. Camera capture and image handling use OpenCV. Face recognition uses the `face_recognition`/dlib embeddings (or InsightFace/ArcFace for higher accuracy). Object detection uses YOLOv8 via Ultralytics; scene description uses a compact vision-language model such as Moondream or SmolVLM served locally, optionally through Ollama. Speech recognition uses Whisper with a Silero voice-activity detector; speech synthesis uses an offline engine such as pyttsx3 or Piper. The backend that ties modules together is written in Python with FastAPI and WebSockets. Visitor history is stored in SQLite (or PostgreSQL for a product). The mobile app is built with Flutter for a single iOS/Android codebase, with push notifications via Firebase Cloud Messaging. On the embedded side, the ESP32-CAM firmware is written with the Arduino/ESP-IDF toolchain and streams MJPEG over Wi-Fi. This stack was chosen for being free, well-documented, locally runnable, and within an AI & Data Science student's skill set.

---

## 17. Hardware Specification and Bill of Materials

During development, no special hardware is required beyond the student's laptop and its webcam. For the deployed prototype, the door unit is built from inexpensive parts:

| Component | Purpose | Approx. ₹ |
|---|---|---|
| ESP32-S3 camera module (e.g. XIAO ESP32S3 Sense — camera + mic) | Capture image and audio | 1,000–1,200 |
| Speaker (I2S/amplified) | Play replies at the door | 300 |
| PIR motion sensor | Wake on approach | 100 |
| Push button + status LED + wiring | Doorbell + indicator | 200 |
| Battery (18650) + charging circuit | Power | 600 |
| Enclosure | Housing | 300 |
| Laptop (owned) | AI server | 0 |
| **Prototype total** | | **≈ ₹2,700** |

The choice of an ESP32-S3 module with a built-in microphone avoids a common pitfall: the standard AI-Thinker ESP32-CAM has **no** microphone, so a design that records audio must either add an I2S mic or, more simply, handle the audio through the phone during a live call. The whole door unit is kept intentionally low-cost because all heavy computation happens on the AI server, not on the door.

---

## 18. Development Methodology and Phases

The project follows an incremental, module-by-module methodology so that there is always a working system, even in early stages. Development proceeds in phases: first, the camera pipeline and a live preview; second, face recognition producing known/unknown labels; third, object and scene understanding; fourth, speech recognition and the voice-activity detector; fifth, the Context Engine fusing everything into a Visitor Event; sixth, the Accessibility Response Engine with both Blind and Deaf modes; seventh, the visitor history and database; eighth, the two-way communication feature; ninth, migration from the laptop webcam to the ESP32-CAM by changing only the camera source; and finally, testing with real users, tuning of thresholds, and preparation of the report and demonstration. Because each module has a defined input and output centred on the Visitor Event, they can be developed and tested largely in parallel by a team, then integrated with minimal friction.

---

## 19. Cost Analysis

For the **student prototype**, the cost is essentially the door-unit parts (about ₹2,700) since the laptop serves as the AI brain at no additional cost — comfortably within the ₹5,000 budget. For a **productised version**, the economics hinge on where the AI runs. If the AI runs in the cloud, the door unit's bill of materials at small batch is roughly ₹3,000 and the business model resembles existing smart doorbells: sell the device and charge a modest monthly subscription for the AI features. If the AI runs locally on a home edge device for privacy, an NVIDIA Jetson-class box adds roughly ₹18,000–25,000, positioning the product as a premium, subscription-free, fully private appliance — a genuine gap in the market. Reaching a sellable product also entails refined prototypes with custom PCBs, certification, and an initial manufacturing batch, which move the figures into the lakhs; these are noted for completeness but are beyond the scope of the academic project.

---

## 20. Testing and Evaluation Plan

The system will be evaluated on both technical and human dimensions. Technically, face recognition will be measured for accuracy (correct name), false-accept and false-reject rates across varied lighting; object and scene understanding will be checked against a set of staged scenarios (delivery with parcel, guest with flowers, service worker with a toolbox, unknown empty-handed visitor); speech transcription will be evaluated for word accuracy in quiet and noisy conditions; and end-to-end latency (from doorbell press to spoken announcement) will be timed, with a target of a few seconds. On the human dimension, the most important evaluation is qualitative testing with blind and deaf users (or blindfolded and muted proxies where real users are unavailable), observing whether the announcements are clear, timely, correctly prioritised, and genuinely useful, and iterating on wording and thresholds accordingly.

---

## 21. Expected Outcomes

The expected outcome is a working demonstrator in which, when a visitor arrives, the system correctly announces a registered household member by name, describes an unknown visitor and the objects they carry, infers a plausible intent, transcribes and relays the visitor's speech, and enables a two-way exchange — all delivered appropriately in Blind or Deaf mode, and logged to a visitor history. A compelling demonstration sequence involves a blindfolded participant "inside" while, in turn, a registered team member, a person carrying a parcel, a person with a toolbox, and a stranger approach the door, each producing a distinct and correct announcement. Beyond the demo, the project is expected to yield a reusable, well-documented codebase, a small curated dataset of visitor scenarios (a genuine data-science contribution), and a clear path toward a real product.

---

## 22. Novelty and Contribution

AccessAI's novelty lies in integration and reframing rather than in any single algorithm. Specifically: it reframes the doorbell as an **accessibility device** serving blind and deaf users from one platform, rather than a security device for sighted, hearing owners; it introduces a **multi-signal Context Engine** that fuses face, objects, scene, speech, time, and history into a single *likely* intent, going beyond the face-only recognition of commercial doorbells; it provides **two-way doorstep communication** for deaf users, largely absent from existing products; it operates **locally and privately**, storing embeddings rather than photographs and keeping data inside the home; and it contributes a **curated dataset** of visitor scenarios suited to the local context. Each of these is a defensible contribution, and together they constitute a system that does not currently exist in the mainstream market.

---

## 23. Ethical Considerations and Privacy

Because the system uses cameras, microphones, and face recognition, ethics and privacy are treated as first-class design concerns rather than afterthoughts. All processing is designed to run locally so that images and audio need not leave the home. The face database stores mathematical embeddings, not raw photographs, reducing the harm of any data exposure. Non-registered faces can be blurred in stored footage. The system is explicit about uncertainty — it reports intent as "likely," never as fact — to avoid users placing unwarranted trust in an automated judgement about a stranger. Visitors' privacy is respected by limiting recording to trigger events rather than continuous surveillance. These choices are not only ethically sound but also form a strong part of the project's argument and its potential commercial differentiation: a doorbell that is genuinely private by design.

---

## 24. Limitations

The system has honest limitations that should be acknowledged. Intent is inferred from visible cues and can be wrong; it is a helpful hint, not a guarantee. Accuracy degrades in poor lighting, and the low-resolution embedded camera is weaker than a laptop webcam. Vision-language models can occasionally produce inaccurate descriptions, which is why a rule-based fallback is retained as a safety net. Running several models together introduces latency, mitigated by analysing a single triggered snapshot rather than continuous video. The embedded door unit has limited compute, so heavier features (continuous behaviour analysis, large vision models) are reserved for a more powerful edge device or the cloud. These limitations do not undermine the project; naming them clearly demonstrates engineering maturity and frames a credible future-work agenda.

---

## 25. Future Scope

Future development can extend AccessAI in several directions: support for multiple cameras and doors through an event-driven architecture; deployment of the AI on a dedicated edge device such as a Jetson for a fully offline, subscription-free product; richer language support and real-time translation for multilingual households; integration with smart locks so a trusted, verified visitor can be granted access; emergency-contact alerts triggered by distress cues; and continual, on-device learning that personalises recognition to each household over time. The modular, data-model-centred design means each of these can be added without rebuilding the core, making AccessAI a platform rather than a fixed product.

---

## 26. Team Roles

For a four-member team, the work divides cleanly. One member owns face recognition — enrolment, embeddings, matching, and anti-spoofing. A second owns the vision and scene modules — object detection, the vision-language model, and the visitor-scenario dataset. A third owns the backend, Context Engine, speech pipeline, and event/database layer. A fourth owns the door hardware (ESP32 firmware and streaming), the mobile app, the accessibility output (text-to-speech, notifications, two-way chat), and the demonstration. Because every module communicates through the shared Visitor Event, the members can work in parallel and integrate with minimal conflict.

---

## 27. Conclusion

AccessAI reimagines one of the most familiar objects in the home — the doorbell — as an intelligent accessibility companion for people who are blind or deaf. By combining face recognition, scene understanding, speech recognition, and speech synthesis, and by fusing them through a conservative Context Engine into a single, clearly communicated Visitor Event, the system converts a meaningless chime into meaningful, actionable understanding: who is at the door, what they carry, why they are likely there, and what they are saying. Delivered through a Blind Mode and a Deaf Mode, and backed by two-way communication and a private, local-first design, AccessAI restores independence, safety, and dignity to users that mainstream products overlook. It is buildable today from affordable, proven components for under ₹5,000, it grows naturally from a laptop prototype to embedded hardware and toward a real product, and its accessibility-first integration is a genuine, defensible contribution. In short, AccessAI is both a strong final-year engineering project and a meaningful step toward technology that includes everyone.

---

## 28. Indicative References / Tools

- OpenCV (computer vision and camera handling)
- dlib / `face_recognition`, InsightFace (ArcFace) — face embeddings
- Ultralytics YOLOv8 — object detection
- Moondream, SmolVLM, Qwen2.5-VL, LLaVA — vision-language models
- OpenAI Whisper, Silero VAD — speech recognition and voice activity detection
- Piper / pyttsx3 — text-to-speech
- FastAPI, WebSockets — backend
- Flutter, Firebase Cloud Messaging — mobile app and notifications
- ESP32-CAM / ESP32-S3, Arduino / ESP-IDF — embedded door unit
