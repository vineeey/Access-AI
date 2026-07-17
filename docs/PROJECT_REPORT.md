# AccessAI — Detailed Project Report

**AI-Powered Smart Accessibility Doorbell for Blind & Deaf People**

_Status as of this report: **Phase 1 complete** (software, laptop-first). Phases 2–6 pending._

---

## 1. Executive Summary

AccessAI is an intelligent doorbell that perceives a visitor on behalf of a blind
or deaf user and communicates that understanding through the sense the user
actually has. It replaces the meaningless chime with a sentence like:

> "Rahul is at the front door. He is carrying a parcel. He said, 'Package for you.'"

- **Blind Mode** → spoken announcement + phone vibration.
- **Deaf Mode** → large on-screen text, live captions, two-way text↔speech chat.

Everything runs **locally** (privacy-first, no cloud, no subscription). Built
entirely from free, open-source models. Prototype hardware budget < ₹5,000; the
laptop is the AI brain during development, and a one-line config change swaps in
an ESP32-CAM later.

**Core novelty:** not any single model, but the accessibility-first *integration*
of face recognition + scene understanding + speech + a conservative context
engine into one coherent assistant for users mainstream doorbells ignore.

---

## 2. Problem & Motivation

An ordinary doorbell communicates one fact — "somebody is here" — through sound.
- A **deaf** person may not perceive the chime at all, and once at the door
  cannot hear the visitor or be easily understood.
- A **blind** person hears the chime but learns nothing about *who* is outside
  or *why*, forcing a choice between dependence and risk.

Existing smart doorbells (Ring, Nest, Amazon) just move the same
video-and-audio interaction onto a phone screen — still assuming the user can
see and hear. **No affordable, accessibility-first doorbell exists that perceives
the visitor for the user and communicates through their available sense.**

---

## 3. Aim & Objectives

**Aim:** Design an AI doorbell that interprets visitors for blind/deaf users and
delivers that through accessible channels.

**Objectives:**
1. Capture image (+ audio on request) at a doorbell/motion trigger.
2. Recognise known household members by face.
3. Describe unknown visitors and their carried objects.
4. Infer likely intent (delivery / guest / unknown) *without overstating*.
5. Transcribe and, where needed, translate the visitor's speech.
6. Deliver via Blind Mode (voice+vibration) and Deaf Mode (text+captions+2-way).
7. Keep a searchable visitor history.
8. Keep processing local and private; prototype < ₹5,000.
9. Same code runs on laptop webcam now and ESP32-CAM later (config switch only).

---

## 4. System Architecture

Three cooperating tiers:

1. **Doorbell Unit** — laptop webcam now; ESP32-CAM (button, LED, mic, PIR)
   later. Only captures and transmits; deliberately dumb.
2. **AI Processing Server** — the laptop. Runs all models + the context/fusion
   engine + accessibility engine.
3. **User Interface** — web dashboard now; Flutter mobile app later. Same
   backend API serves both.

```
Webcam / (later) ESP32-CAM
        │
        ▼   trigger (button / motion / manual)
   capture snapshot (+ audio)
        │
   ┌────┴───────────────────────────────┐
   ▼                                    ▼
Face pipeline                     Vision pipeline
 detect → anti-spoof → InsightFace   YOLO objects
 → known / unknown                   (skip VLM if known)
   │                                    │
   │                               VLM scene desc
   │                               OCR on parcels
   └───────────────┬────────────────────┘
                   ▼
             Speech pipeline
             VAD → Whisper → langdetect → translate
                   │
                   ▼
             Visitor Re-ID (unknowns only)
                   │
                   ▼
             CONTEXT ENGINE  →  Visitor Event  (the spine)
                   │
   ┌───────────────┼────────────────┐
   ▼               ▼                ▼
 Blind Mode     Deaf Mode        History (SQLite)
 TTS + vibrate  text + captions   + snapshots
                + 2-way chat
```

### 4.1 The Visitor Event — the backbone

The whole system is unified by one data object. **Every module writes into it;
every output reads from it.** Adding a feature = add a field + have one module
fill it in. No pipeline rework.

```json
{
  "event_id": "evt_20260709_1432_ab12cd",
  "timestamp": "2026-07-09T14:32:10",
  "trigger": "doorbell",
  "identity": { "known": true, "name": "Rahul", "confidence": 0.97 },
  "spoof_score": 0.98, "is_spoof": false,
  "visitor_count": 1,
  "carried_objects": ["a package"],
  "scene_summary": "a man in a casual shirt holding a box",
  "ocr_text": "BlueDart",
  "speech_transcript": "Package for you",
  "language_detected": "en", "translated_transcript": "",
  "reid_id": null, "reid_seen_count": 0,
  "intent": "known visitor", "confidence": 0.9,
  "announcement_text": "Rahul is at the door. Carrying a package.",
  "snapshot_path": "data/history/evt_20260709_1432_ab12cd.jpg"
}
```

---

## 5. What Is Built (Phase 1) — Current Code State

Location: `~/AccessAI/`

| File | Role | Status |
|---|---|---|
| `config.py` | All tunables (camera, thresholds, feature flags, courier keywords) | ✅ Done |
| `run.py` | Entrypoint: camera thread + uvicorn server | ✅ Done |
| `requirements.txt` | Pinned deps (Piper removed — see §8) | ✅ Done |
| `accessai/camera.py` | Webcam/MJPEG abstraction (ESP32-ready) | ✅ Existing, kept |
| `accessai/visitor_event.py` | The data spine (dataclasses) | ✅ Extended |
| `accessai/face_module.py` | InsightFace `buffalo_l`, cosine matching | ✅ Rewritten |
| `accessai/vision_module.py` | YOLOv8n object detection | ✅ Done |
| `accessai/context_engine.py` | Fuses signals → VisitorEvent + rule-based intent | ✅ Done |
| `accessai/accessibility.py` | Composes announcement, routes Blind/Deaf | ✅ Done |
| `accessai/tts_module.py` | Piper → pyttsx3 fallback | ✅ Done |
| `accessai/database.py` | SQLite via SQLAlchemy (events, faces, reid, clusters) | ✅ Done |
| `accessai/pipeline.py` | End-to-end runner; honours skip-VLM-for-known | ✅ Done |
| `accessai/server.py` | FastAPI + WebSocket + MJPEG stream | ✅ Done |
| `web/index.html`, `app.js`, `style.css` | Dashboard: live cam, Ring, event card, history, reply, mode toggle | ✅ Done |
| `README.md` | Setup + troubleshooting | ✅ Done |

### Phase 1 capabilities (working end-to-end)
- Live webcam in the browser (MJPEG stream).
- "Ring Doorbell" → runs the full pipeline.
- Face recognition: known → name; else "Unknown".
- Object detection: reports carried items (backpack/handbag/suitcase/book→package).
- Rule-based intent: known visitor / likely delivery / unknown visitor / no visitor.
- Announcement composed and spoken (pyttsx3) + shown in UI.
- Two-way reply box (Deaf Mode): type → laptop speaks at "door".
- Every event saved to SQLite with a snapshot; history list in UI.
- Blind/Deaf/Both mode toggle.

### Key design decisions locked in
- **InsightFace** over dlib (accuracy).
- **Skip-VLM-for-known-faces**: the heavy vision-language model only runs for
  Unknown visitors → roughly halves latency for the common case.
- **Conservative intent language**: "likely delivery", never "definitely".
- **Privacy**: store embeddings, not raw photos, in the DB.
- **Anti-spoof gate at the module boundary**: a "known but spoofed" face is
  downgraded to Unknown before it reaches the context engine.
- **Dropped**: threat/weapon detection (false-positive risk), speech emotion
  (unreliable). **Deferred**: loitering (needs continuous frames).

---

## 6. Remaining Work (Phases 2–6)

### Phase 2 — Safety & richness
- `antispoof.py` — Silent-Face-Anti-Spoofing (ONNX, CPU). Runs before
  recognition; `spoof_score < ANTISPOOF_MIN_SCORE` → treat as Unknown.
- `vlm_module.py` — Moondream/SmolVLM (transformers or Ollama). **Unknowns
  only.** Returns short scene description. Fallback = YOLO-only description.
- `ocr_module.py` — PaddleOCR on parcel-like crops → courier keyword match.
- Flip `ENABLE_ANTISPOOF`, `ENABLE_VLM`, `ENABLE_OCR` in `config.py`.

### Phase 3 — Speech + multi-language
- `speech_module.py` — Silero VAD gate + Whisper transcription.
- `translate_module.py` — langdetect + IndicTrans2/NLLB → user's language.
- Multilingual TTS voice; Deaf-Mode 2-way reply already stubbed (`/reply`).
- Flip `ENABLE_SPEECH`.

### Phase 4 — Memory & smarts
- `reid_module.py` — OSNet (torchreid) body embeddings for repeat unknowns →
  "same unknown visitor, 3rd time today."
- `auto_enroll.py` — DBSCAN over unknown-face embeddings → "Save this visitor?"

### Phase 5 — Voice control (Blind UX)
- `wakeword_module.py` — openWakeWord always-listening + intent parser
  ("who is at the door", "open camera").

### Phase 6 — Hardware & mobile
- Set `CAMERA_SOURCE` to ESP32-CAM MJPEG URL; add `/ring` webhook for the
  physical button. ESP32-S3 Sense (has mic) recommended.
- Flutter app consuming the same FastAPI backend.

**All VisitorEvent fields for these phases already exist** — wiring only.

---

## 7. Technology Stack

- **Vision/camera:** OpenCV
- **Face:** InsightFace (ArcFace `buffalo_l`) + onnxruntime
- **Objects:** Ultralytics YOLOv8n
- **Scene (Phase 2):** Moondream / SmolVLM (optionally via Ollama)
- **OCR (Phase 2):** PaddleOCR
- **Speech (Phase 3):** OpenAI Whisper + Silero VAD
- **Translate (Phase 3):** IndicTrans2 / NLLB
- **Re-ID (Phase 4):** OSNet (torchreid); DBSCAN (scikit-learn)
- **Wake word (Phase 5):** openWakeWord
- **TTS:** pyttsx3 (Piper optional, manual install)
- **Backend:** Python + FastAPI + WebSockets + uvicorn
- **DB:** SQLite (SQLAlchemy)
- **App (later):** Flutter + Firebase Cloud Messaging
- **Door unit (later):** ESP32-S3/ESP32-CAM, MJPEG streaming

---

## 8. Known Issues & Environment Notes

- **Python 3.12 + Piper:** `piper-tts` needs `piper-phonemize`, which has **no
  3.12 wheel**. It was removed from `requirements.txt`; `pyttsx3` is the active
  TTS. This is why the first `pip install` aborted (one bad dep kills the whole
  resolve). To use Piper later, install its binary + a voice file manually.
- **pyttsx3 on Linux** needs `espeak`: `sudo apt install -y espeak alsa-utils`.
- **First run is heavy:** torch (~2 GB), InsightFace model (~300 MB), YOLO
  weights, all download once.
- **Webcam:** on native Linux `CAMERA_SOURCE = 0`. If no `/dev/video*`, use a
  phone IP-camera app and point `CAMERA_SOURCE` at its URL (same trick as ESP32).

---

## 9. Testing & Verification Plan

**Phase 1 (do now):**
1. Add `data/known_faces/YourName/1.jpg`, restart → log shows loaded face.
2. Ring → announcement includes your name; TTS speaks it.
3. Remove photo → Ring → "unknown visitor."
4. Hold a bag/box → announcement mentions carried object.
5. Type in reply box → laptop speaks it.
6. History list shows events with snapshots.

**Later phases:** hold a phone-photo of a face → caught as spoof (P2); parcel
label → courier read (P2); speak Hindi → translated announcement (P3); same
stranger twice → "seen ×2" (P4); "Hey Access, who's at the door?" (P5).

---

## 10. Ethics & Privacy

- Local processing — images/audio never leave the home.
- DB stores face **embeddings**, not raw photos.
- Non-registered faces can be blurred in stored footage (future).
- System is explicit about uncertainty ("likely," never fact).
- Recording is trigger-based, not continuous surveillance.

---

## 11. Limitations (stated honestly)

Intent is inferred from visible cues and can be wrong. Accuracy degrades in poor
light; the embedded camera is weaker than a webcam. VLMs can mis-describe (hence
the rule-based fallback). Running several models adds latency (mitigated by
analysing one triggered snapshot, not continuous video).

---

## 12. Cost

- **Student prototype:** door-unit parts ≈ ₹2,700 (laptop is the free AI brain)
  → within ₹5,000.
- **Product, cloud AI:** door unit ≈ ₹3,000 + subscription model.
- **Product, local edge AI (private):** + Jetson-class box ≈ ₹18k–25k → premium,
  subscription-free, fully private appliance (a real market gap).
