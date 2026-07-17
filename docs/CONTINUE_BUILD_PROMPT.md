# Handoff Prompt — Continue Building AccessAI in VS Code with Claude

Copy everything in the block below and paste it as your **first message** to
Claude (Claude Code / the agent) after opening the `~/AccessAI` folder in VS Code.

---

```
You are continuing an existing project called AccessAI — an AI-powered
accessibility doorbell for blind and deaf users. The project root is this folder
(~/AccessAI). Phase 1 is already built and working. Your job is to build Phases
2 through 5 on top of it WITHOUT breaking Phase 1.

## First: read these files to load full context
- docs/PROJECT_REPORT.md   (complete project overview + current state)
- docs/AccessAI_Project_Note.md  (the ~5000-word vision doc)
- config.py                (all feature flags and tunables)
- accessai/visitor_event.py (the data spine — every module reads/writes this)
- accessai/pipeline.py      (the end-to-end orchestrator you'll extend)
- accessai/context_engine.py (where intent is decided)
- README.md

## Non-negotiable architecture rules (do not violate)
1. The VisitorEvent dataclass (accessai/visitor_event.py) is the single source
   of truth. Every module WRITES into it; every output READS from it. To add a
   feature: fill an existing field (they already exist for all phases) — do NOT
   restructure the pipeline.
2. Each new AI capability is its own module in accessai/ with a clean
   available()/graceful-fallback pattern, exactly like face_module.py and
   vision_module.py. If a heavy dependency is missing, the module must degrade
   gracefully (log a hint, return empty) — never crash the app.
3. Every heavy feature is gated by a flag in config.py (ENABLE_ANTISPOOF,
   ENABLE_VLM, ENABLE_OCR, ENABLE_SPEECH, etc.), defaulting to False so the base
   app always runs.
4. Wire new modules into accessai/pipeline.py — the constructor already accepts
   antispoof=, vlm=, ocr=, speech=, translate=, reid= and their *_enabled flags.
   Instantiate them in run.py and pass them in.
5. Skip-VLM-for-known-faces optimization must be preserved: the VLM only runs
   when the largest detected face is Unknown.
6. Intent language stays conservative ("likely delivery", never "definitely").
7. Camera stays behind accessai/camera.py so the ESP32 swap remains one config
   line. Do not hardcode a camera source anywhere else.
8. Target environment: Python 3.12, Linux, CPU-only. Prefer CPU-friendly models.
   Note: piper-tts is NOT installable on 3.12 (piper-phonemize has no wheel);
   TTS uses pyttsx3. Do not re-add piper-tts to requirements.txt.

## Build order (do phases in this order; verify each before moving on)

### Phase 2 — Safety & richness
- accessai/antispoof.py: Silent-Face-Anti-Spoofing (ONNX, CPU). Expose
  score(frame_bgr, box) -> float in [0,1] (1=real). Wire into pipeline BEFORE
  recognition is trusted: if enabled and score < config.ANTISPOOF_MIN_SCORE,
  the context engine already downgrades to Unknown via is_spoof — just feed it
  the score (pipeline already computes spoof_score; implement the module it
  calls).
- accessai/vlm_module.py: describe(frame_bgr) -> short str. Use Moondream2 via
  transformers (or Ollama if available). UNKNOWNS ONLY. Fallback to "".
- accessai/ocr_module.py: read(crop_bgr) -> str using PaddleOCR. Pipeline
  already crops parcel-like objects and calls ocr.read(); implement the module.
  Courier keyword list is in config.COURIER_KEYWORDS.
- Add the new deps to requirements.txt (uncomment/add), flip the ENABLE_* flags,
  instantiate in run.py, pass into Pipeline(...).

### Phase 3 — Speech + multi-language
- accessai/speech_module.py: transcribe(audio_bytes) -> (text, lang_code).
  Silero VAD gate + Whisper (config.WHISPER_MODEL, default "tiny").
- accessai/translate_module.py: to_english(text, src) and to_user_lang(text) via
  IndicTrans2/NLLB. User language is config.USER_LANGUAGE.
- Capture a short audio clip on trigger (add mic capture in server.py /trigger,
  or a separate endpoint). Pipeline.run_once already accepts audio_bytes.
- The Deaf-Mode two-way /reply endpoint already exists (TTS a typed reply).

### Phase 4 — Memory & smarts
- accessai/reid_module.py: identify_or_enroll(frame_bgr) -> (reid_id,
  seen_count) using OSNet (torchreid) body embeddings stored in the reid_gallery
  table (accessai/database.py already has ReidRow). UNKNOWNS ONLY.
- accessai/auto_enroll.py: background DBSCAN over recent unknown face embeddings
  (unknown_face_clusters table exists); when a cluster hits N sightings, surface
  a "Save this visitor?" item via a new GET /suggestions endpoint + UI card.

### Phase 5 — Voice control (Blind UX)
- accessai/wakeword_module.py: openWakeWord always-listening thread; on wake
  word, parse a simple intent ("who is at the door" -> speak last event,
  "open camera", "read history"). Off by default behind a config flag.

## How to verify each phase (run it, don't just typecheck)
- Start: `source .venv/bin/activate && python3 run.py`, open http://localhost:8000
- P2: hold a phone showing a face photo -> announced as Unknown (spoof caught);
  hold a box with a courier label -> announcement reads the courier name.
- P3: speak another language during a ring -> transcript + translation shown,
  announcement in USER_LANGUAGE.
- P4: trigger the same unknown person twice -> "seen ×2"; 5+ times -> a
  "Save this visitor?" suggestion appears.
- P5: say the wake word + "who is at the door" -> it speaks the last event.

## Coding style
- Match the existing code: module-level try/except import guards, an
  available() method, print("[ModuleName] ...") logging, docstrings that explain
  WHY (see face_module.py / vision_module.py as templates).
- Pin new dependency versions in requirements.txt and keep them CPU-friendly.
- Keep the app runnable at every commit: base app must start even if every
  optional dependency is uninstalled.

Start by reading the files listed above, then confirm your understanding and
propose a short plan for Phase 2 before writing code.
```

---

## Tips for using this in VS Code

1. Open the `~/AccessAI` folder as your workspace so Claude has file access.
2. Make sure the venv is active in the integrated terminal
   (`source .venv/bin/activate`) so Claude can run and test the app.
3. Do **one phase per session** — verify it works before starting the next.
4. Commit after each working phase (`git init` first if you haven't):
   ```bash
   git add -A && git commit -m "Phase N: <feature>"
   ```
5. If a model download is huge or slow, tell Claude your constraints (CPU-only,
   limited disk) and it will pick lighter model variants.
