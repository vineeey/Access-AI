# PHASE 11 PROMPT — Natural Human-Like Voice (Kokoro-ONNX + edge-tts + in-app voice picker)

An ADD-ON phase after the 10-phase build. Replaces the robotic espeak/pyttsx3
voice with natural, human-like TTS. Paste EVERYTHING in the fenced block below as
your next message to the Claude agent in VS Code (the `AccessAI` workspace with
Phases 1–10 complete).

---

```
You are enhancing the completed AccessAI project (Phases 1–10 done). Build ONLY
this add-on: replace the robotic espeak/pyttsx3 voice with NATURAL, human-like
speech using Kokoro (ONNX, offline) as the PRIMARY engine and edge-tts (online
Microsoft Neural voices) as a FALLBACK, plus an IN-APP VOICE PICKER on the
dashboard. Do not change any other feature's behaviour.

====================================================================
CRITICAL PRE-FLIGHT — PROTECT THE TORCH VERSION (this is why we chose ONNX)
====================================================================
The ML stack is PINNED and WORKING: torch==2.4.1 torchvision==0.19.1
torchaudio==2.4.1. In Phase 7 an ML install silently downgraded torch and BROKE
YOLO (predict() returned 0 detections, NO error). The STANDARD `kokoro` pip
package depends on torch and CAN move it — DO NOT install that. Use `kokoro-onnx`
(onnxruntime-based; onnxruntime is already a dependency) and `edge-tts` (pure
async HTTP, no torch). Neither should touch torch.

MANDATORY around every install:
- BEFORE: python -c "import torch,torchvision; print(torch.__version__, torchvision.__version__)"
- Install with care; if ANY package tries to change torch/torchvision/torchaudio,
  pin the trio in the same command or abandon that package.
- AFTER: confirm torch is STILL 2.4.1 AND YOLO bus.jpg still detects (bus +
  multiple persons, NOT zero). Report before/after + the YOLO check. Non-negotiable.

====================================================================
GOAL
====================================================================
The doorbell should sound like a natural human (GPT/Gemini-voice quality), not a
1990s robot. Primary: Kokoro-ONNX offline (private, no network). Fallback: edge-tts
online neural voices (used only if Kokoro is unavailable OR the user selects an
edge voice). The user can pick the voice live from the dashboard. Everything must
degrade gracefully: if BOTH are unavailable, fall back to the existing pyttsx3 so
the system never goes silent.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing:
- config.py                  (existing TTS section: ENABLE_TTS, TTS_RATE,
                              TTS_VOLUME, TTS_VOICE — extend, don't break)
- accessai/tts_module.py     (CURRENT TTSModule: single worker thread + queue,
                              speak(text), available(), engine_name(). This is the
                              interface the whole app already calls — PRESERVE IT.)
- accessai/accessibility.py  (calls tts.speak(...) — must keep working unchanged)
- accessai/server.py         (/reply and voice routes call speak; add voice routes)
- run.py                     (builds TTSModule from config)
- web/index.html, app.js, style.css (add the voice picker UI)

HARD REQUIREMENT: keep the PUBLIC interface of the TTS layer identical —
speak(text), available(), engine_name(), and the non-blocking single-worker-thread
+ queue design (so /trigger and /reply never block on audio). The rest of the app
must NOT need any change to how it calls TTS. Restate understanding in 3-4 bullets
before coding.

====================================================================
AUDIO PLAYBACK NOTE (important)
====================================================================
Kokoro-ONNX and edge-tts produce AUDIO SAMPLES / audio files, not direct speaker
output (unlike pyttsx3 which speaks directly). You must PLAY the audio:
- Kokoro-ONNX returns a numpy float32 waveform + sample rate (24000). Play it via
  `sounddevice` (already installed in Phase 7): sd.play(samples, sr); sd.wait().
- edge-tts returns MP3 bytes; decode + play (use `soundfile`+`sounddevice`, or
  write a temp wav and play, or use `miniaudio`/`playsound`). Prefer a path that
  needs the FEWEST new deps. If you add `soundfile`, pin it and re-check torch.
- ALL playback happens INSIDE the existing TTS worker thread (never on the request
  thread). Guard playback in try/except so a missing audio device logs once and
  degrades (text still shown in UI) — reuse the headless-safe pattern.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Add pinned (verify torch-safe):
  kokoro-onnx==0.4.9        # or latest that installs cleanly on 3.12/CPU
  edge-tts==6.1.19          # async Microsoft Neural voices (online fallback)
  soundfile==0.12.1         # only if needed to decode edge-tts mp3; else omit
Comment: kokoro-onnx uses onnxruntime (already present) — NOT torch. edge-tts is
pure HTTP. Neither should move torch; verify after install. Note the Kokoro model
files (kokoro-v*.onnx ~310MB + voices-*.bin ~26MB) download once — document where
they go (models/kokoro/) and the URL/source in a comment.

--- 2) config.py — extend the TTS section (keep existing keys working) ---
Add:
  TTS_ENGINE = "kokoro"        # "kokoro" | "edge" | "pyttsx3" (auto-fallback order)
  TTS_MODEL_DIR = os.path.join(BASE_DIR, "models", "kokoro")
  KOKORO_VOICE = "af_heart"    # default warm female; user can change in-app
  KOKORO_SPEED = 1.0           # 0.5–2.0
  KOKORO_LANG = "en-us"
  EDGE_VOICE = "en-US-AriaNeural"   # natural fallback; en-IN-NeerjaNeural for India
  EDGE_RATE = "+0%"
  # Voices offered in the dashboard picker (label -> engine + voice id):
  VOICE_CHOICES = [
     {"id":"kokoro:af_heart",  "label":"Heart (female, warm) — offline"},
     {"id":"kokoro:af_bella",  "label":"Bella (female) — offline"},
     {"id":"kokoro:af_sarah",  "label":"Sarah (female, neutral) — offline"},
     {"id":"kokoro:af_nicole", "label":"Nicole (female, soft) — offline"},
     {"id":"kokoro:am_michael","label":"Michael (male) — offline"},
     {"id":"edge:en-US-AriaNeural",  "label":"Aria (female) — online neural"},
     {"id":"edge:en-IN-NeerjaNeural","label":"Neerja (female, Indian) — online"},
     {"id":"edge:hi-IN-SwaraNeural", "label":"Swara (Hindi female) — online"},
  ]
Keep ENABLE_TTS, TTS_RATE, TTS_VOLUME (pyttsx3 uses rate/volume; kokoro uses speed).
Comment that the model auto-downloads once and offline Kokoro is the private default.

--- 3) accessai/tts_module.py — REWRITE internals, KEEP the interface ---
Refactor into a multi-backend engine behind the SAME public methods. Structure:

  # guarded imports, each sets a capability flag:
  #   kokoro_onnx (Kokoro class)            -> self._has_kokoro
  #   edge_tts                              -> self._has_edge
  #   sounddevice, numpy, soundfile         -> playback
  #   pyttsx3 (existing)                    -> last-resort

  class TTSModule:
    __init__(self, enabled=True, engine="kokoro", voice="af_heart",
             model_dir=..., speed=1.0, edge_voice="en-US-AriaNeural",
             rate=165, volume=1.0, lang="en-us"):
       - Keep the SINGLE daemon worker thread + queue.Queue design from the current
         module. The worker owns whichever backend is active and plays audio.
       - Resolve the active backend at init in this order based on `engine` and
         availability: requested engine -> kokoro -> edge -> pyttsx3. Log the chosen
         one. Lazy-load Kokoro model on first speak (don't block startup on the
         ~310MB load; log "loading Kokoro voice (first run downloads models)").
    available(self) -> bool: any backend usable.
    engine_name(self) -> str: "kokoro" | "edge" | "pyttsx3" | "none".
    current_voice(self) -> str: e.g. "kokoro:af_heart".
    list_voices(self) -> list: config.VOICE_CHOICES (+ mark which are available).
    set_voice(self, voice_id) -> tuple[bool,str]:
       - Parse "engine:voice". Switch the active backend + voice for FUTURE
         utterances (thread-safe; set via the worker or a lock). If the target
         engine is unavailable (e.g. edge chosen but offline), return (False,
         reason) and keep the current voice. Persist choice in memory (and
         optionally to a small json in data/ so it survives restart — optional).
    speak(self, text) -> None:
       - Unchanged signature. Enqueue text; the worker synthesises with the active
         backend and plays it. Never block the caller. Drop stale items if flooded.

    Worker synthesis details:
       - Kokoro: kokoro = Kokoro(model_path, voices_path); samples, sr =
         kokoro.create(text, voice=<voice>, speed=<speed>, lang=<lang>);
         sd.play(samples, sr); sd.wait().
       - edge: run the async edge_tts.Communicate(text, voice).save(tmp.mp3) inside
         the worker (use asyncio.run in the thread); decode mp3 -> samples -> play;
         clean up temp file. If offline/HTTP fails, log once and fall back to
         kokoro/pyttsx3 for THIS utterance.
       - pyttsx3: the existing path (rate/volume), as last resort.
    Guard EVERY backend call in try/except so one failing utterance never kills the
    worker thread (log once, continue). If playback device is missing (headless),
    skip audio gracefully (text already goes to the UI).

--- 4) run.py — build TTSModule with the new config ---
Pass the new args (engine, voice, model_dir, speed, edge_voice, lang) from config.
Log the resolved engine + voice on startup. App MUST start if Kokoro/edge are
missing (falls back to pyttsx3, or text-only if even that is absent).

--- 5) server.py — voice picker routes ---
- GET "/voices": return tts.list_voices() (id, label, available) + current voice +
  active engine. For the dashboard picker.
- POST "/voice" {"id":"kokoro:af_bella"}: tts.set_voice(id) -> {ok, message,
  engine, voice}. On success, SPEAK a short confirmation in the new voice
  ("Voice changed. This is how I sound now.") so the user hears the change.
- GET "/tts_status": {enabled, engine, voice, kokoro:bool, edge:bool,
  pyttsx3:bool}.
Keep /reply working unchanged (it just calls speak).

--- 6) web UI — the voice picker ---
- A "Voice" dropdown in settings (near the Mode selector), populated from
  GET /voices, showing which are offline vs online. Selecting one POSTs /voice;
  show the returned message; the system speaks a sample so the user hears it.
- A small "🔊 Test voice" button that POSTs /reply {"text":"Hello, this is your
  AccessAI doorbell speaking."} so they can preview without a real doorbell event.
- Reflect the active engine in the existing status pills ("Voice: Kokoro af_heart").
- Vanilla JS, no CDN.

--- 7) Update the /status health panel (Phase 10) ---
Add the TTS engine + voice + backend availability to GET /status so the health
panel shows "Voice: kokoro (af_heart) ✓" and flags if it fell back to pyttsx3.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. torch before/after + YOLO bus.jpg sanity (MANDATORY).
2. Which engine is active (kokoro / edge / pyttsx3) and why. Confirm Kokoro model
   downloaded + loaded (or, if the ~310MB download can't happen in the sandbox,
   say so and show the edge/pyttsx3 fallback engaging gracefully).
3. Speak test: POST /reply {"text":"Rahul is at the door. He is carrying a parcel."}
   -> confirm it synthesised + played (or, headless, that it synthesised samples
   without error and playback was skipped gracefully). Report engine used + that
   the OUTPUT is natural (if you can save the wav, note its duration/sample rate).
4. Voice switch: GET /voices (paste it), POST /voice {"id":"kokoro:af_bella"} ->
   confirm the active voice changed and a confirmation was spoken. Try switching to
   an edge voice; if offline, confirm the graceful (False, reason) response and no
   crash.
5. Non-blocking: confirm speak() still returns immediately (queue+worker) — the
   request thread is never blocked by synthesis/playback.
6. Non-regression: /trigger still speaks announcements (now natural), /reply works,
   Deaf mode unaffected, /status shows the voice. Phases 1–10 all still behave;
   YOLO REAL detections intact. Conservative language preserved.

====================================================================
GUARDRAILS
====================================================================
- TORCH SAFETY: never install the torch-based `kokoro` package; use `kokoro-onnx`.
  Verify torch 2.4.1 + YOLO after any install.
- KEEP the TTS public interface identical (speak/available/engine_name) and the
  non-blocking single-worker-thread+queue design — the whole app depends on it.
- ALL synthesis + playback happens in the worker thread, never on the request path.
- Graceful fallback chain: requested engine -> kokoro -> edge -> pyttsx3 -> text-only.
  The system must NEVER go silent-and-crash; worst case is text-only.
- edge-tts needs internet; treat any network failure as a per-utterance fallback,
  not a crash. Offline is the default (Kokoro).
- Guard playback for headless/no-audio: skip audio, keep text in UI.
- Do not open a camera outside accessai/camera.py. Do not rename VisitorEvent
  fields/DB methods. Match existing style (guarded imports, available(), WHY-docs).

FIRST restate understanding + list files to modify. THEN build. THEN run
verification (INCLUDING torch + YOLO) and report real output, fixing errors before
finishing.
```

---

## Before you paste — nothing to install manually
The agent installs `kokoro-onnx` + `edge-tts` itself. Just be ready for a one-time
**~310MB Kokoro model download** on the first spoken output (it's offline forever
after that).

## After it's done, send me a report with:
1. **torch before/after + YOLO sanity** (Kokoro is ONNX so it *should* be safe —
   but we verify, given Phase 7).
2. Which engine went active (kokoro / edge / pyttsx3) + confirmation the Kokoro
   model loaded.
3. The `/voices` list + a voice-switch result (Heart → Bella) that spoke a sample.
4. Confirmation the announcement now sounds natural (and that `speak()` is still
   non-blocking).
5. Any errors + fixes; Phases 1–10 non-regression (especially YOLO still detecting).

## Note on the voices
- **Offline (Kokoro):** `af_heart`, `af_bella`, `af_sarah`, `af_nicole` (female),
  `am_michael` (male) — private, no internet.
- **Online (edge-tts):** `en-IN-NeerjaNeural` (Indian-accented English) and
  `hi-IN-SwaraNeural` (Hindi) are in the picker — those pair beautifully with your
  Phase 8 translation for a multilingual demo, but they need internet at speak time.

Default is **`af_heart`** — warm female, offline. You can switch live from the
dashboard picker. This single change will do more for the *feel* of your demo than
almost anything else — a blind user hearing a warm human voice instead of a robot
is the whole point.
