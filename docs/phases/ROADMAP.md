# AccessAI — 10-Phase Build Roadmap

Each phase ends with a **working, demoable system**. Build one phase per session
in VS Code with the Claude agent. After each phase, verify it works, then request
the next phase's prompt.

| Phase | Title | What you can demo at the end |
|---|---|---|
| **1** | **Foundation** — scaffold, config, VisitorEvent spine, camera, FastAPI + web dashboard, SQLite, manual trigger | Live webcam in browser; click "Ring" → an event is created ("Someone is at the door"), saved to history with a snapshot |
| **2** | **Face Recognition** (InsightFace) | Ring → recognises a registered person by name, else "Unknown visitor" |
| **3** | **Object & Scene Detection** (YOLOv8) + Context Engine intent | Ring → "Unknown visitor carrying a backpack. Likely a delivery." |
| **4** | **Accessibility Output** — TTS + Blind/Deaf modes + 2-way reply | Announcement is spoken aloud; Deaf-mode big text; type a reply → spoken "at the door" |
| **5** | **Face Anti-Spoofing / Liveness** | Hold a phone photo of a known face → downgraded to "Unknown" (spoof caught) |
| **6** | **VLM Scene Description + OCR** | Unknown visitor → richer scene sentence; parcel label read → "BlueDart delivery" |
| **7** | **Speech Recognition** (Whisper + VAD) | Visitor speaks → transcript appears and is announced |
| **8** | **Multi-language + Translation** (IndicTrans2/NLLB) | Visitor speaks Hindi → announced/subtitled in your chosen language |
| **9** | **Memory** — Visitor Re-ID (OSNet) + Auto-Enrollment (DBSCAN) | Same stranger twice → "seen ×2"; frequent unknown → "Save this visitor?" |
| **10** | **Wake Word + Voice Commands + Hardening + ESP32/Flutter readiness** | "Hey Access, who's at the door?" → speaks last event; app hardened; one-line ESP32 camera swap documented |

## Rules that hold across ALL phases
1. **VisitorEvent is the spine.** Every module writes into it; every output reads
   from it. Add features by filling fields, not by restructuring the pipeline.
2. **Every heavy feature is behind a flag in `config.py`**, defaulting off, so the
   base app always runs.
3. **Graceful degradation.** If an optional dependency is missing, that module
   logs a hint and returns empty — it never crashes the app.
4. **Camera stays behind `accessai/camera.py`** so the ESP32 swap is one config line.
5. **Conservative language** in announcements ("likely delivery", never "definitely").
6. **Target env:** Python 3.12, Linux, CPU-only. No `piper-tts` (no 3.12 wheel).
7. **Runnable at every commit.** Commit after each working phase.

## Workflow
1. Paste the phase prompt to the Claude agent in VS Code.
2. Let it read context, propose a short plan, then build.
3. Run and verify using the phase's verification checklist.
4. Commit: `git add -A && git commit -m "Phase N: <title>"`.
5. Send the phase report back here → receive the next phase prompt.
