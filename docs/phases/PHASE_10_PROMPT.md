# PHASE 10 PROMPT — Wake Word + Voice Commands + Hardening + ESP32/Flutter Readiness (FINALE)

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–9 complete). This is the
LAST phase — it adds hands-free control, then hardens and documents the whole
system for demo + the hardware/mobile future.

---

```
You are completing the AccessAI project. Phases 1–9 are COMPLETE and verified
(Foundation, Face Recognition, Object Detection + Context/Intent, Accessibility
Output/TTS, Anti-Spoofing, VLM Scene Description + OCR, Speech Recognition,
Translation, Re-ID + Auto-Enrollment). Build Phase 10 now — the FINAL phase:
(A) WAKE WORD + VOICE COMMANDS (hands-free Blind Mode), (B) END-TO-END HARDENING,
(C) ESP32-CAM + Flutter READINESS. Do not add unrelated features.

====================================================================
CRITICAL PRE-FLIGHT — PROTECT THE TORCH VERSION (still applies)
====================================================================
The ML stack is PINNED: torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1.
openWakeWord uses onnxruntime/tflite (should be torch-safe), but you MUST STILL:
- Record torch/torchvision BEFORE any install.
- After installing, confirm torch is STILL 2.4.1 AND YOLO bus.jpg still detects
  (bus + persons, not zero). If tflite-runtime or any dep tries to move torch,
  pin the trio in the same command and re-verify. Report before/after + YOLO.

====================================================================
PART A — WAKE WORD + VOICE COMMANDS
====================================================================
GOAL: a blind user controls AccessAI hands-free. An always-listening detector
hears a wake word ("Hey Access" or a built-in like "hey jarvis"/"alexa"), then a
short command is captured (reuse Phase-7 SpeechModule) and parsed into an intent
that the system acts on and SPEAKS the answer via Phase-4 TTS.

STEP 0 — READ FIRST (match interfaces):
- config.py                 (ENABLE_WAKEWORD flag exists; add a Wake-word section)
- accessai/speech_module.py (record + transcribe — REUSE for command capture)
- accessai/tts_module.py    (speak — REUSE to answer)
- accessai/database.py      (recent_events — for "who was at the door")
- accessai/pipeline.py      (run_once — a voice command may TRIGGER a doorbell
                            analysis; latest frame comes from the server holder)
- accessai/server.py        (LatestFrame holder; broadcast; routes)
- run.py                    (threads + injection)

TOOL CHOICE — openWakeWord (CPU, onnxruntime):
  pip install openwakeword (pinned). It ships pretrained models ("hey_jarvis",
  "alexa", "hey_mycroft", etc.) that download on first use. A truly custom
  "Hey Access" model requires training; DO NOT train here. Instead:
   - Use a configurable pretrained wake word (default "hey_jarvis") AND
   - document that a custom "Hey Access" model can be trained later and dropped in.
  If openwakeword can't install/run on 3.12, FALL BACK to a simple push-to-talk:
  a /listen endpoint + a dashboard "🎙 Command" button that records one command
  and parses it (so voice commands still work without the always-on hotword).
  REPORT which path is active.

--- config.py — Wake-word section ---
Keep ENABLE_WAKEWORD; set True at end (but see the "always-on is opt-in" note).
Add:
  WAKEWORD_ENABLED = True
  WAKEWORD_MODEL = "hey_jarvis"      # pretrained; custom "hey_access" is future
  WAKEWORD_THRESHOLD = 0.5
  WAKEWORD_COMMAND_SECONDS = 4       # how long to capture the command after wake
  WAKEWORD_ALWAYS_ON = False         # default OFF (CPU + privacy); button/opt-in
Comment: always-on listening uses CPU continuously and is a privacy choice — off
by default; the user opts in. Push-to-talk works regardless.

--- accessai/wakeword_module.py  (NEW) ---
Mirror the module pattern (guarded imports, available(), logging).
class WakeWordModule:
  __init__(self, model=..., threshold=..., on_wake=callable):
     - guarded import openwakeword; load the model; available() reflects it.
     - on_wake is a callback the module calls when the wake word fires.
  available(self) -> bool ; model_name(self).
  start(self) / stop(self):
     - start a daemon thread that reads mic frames (via sounddevice, 16kHz) and
       feeds openWakeWord; when score >= threshold, call on_wake() (debounced so
       one utterance fires once). Only starts if WAKEWORD_ALWAYS_ON is True.
     - Never crash the app if the mic/model is missing (log once, stay idle).

--- accessai/voice_commands.py  (NEW) — intent parsing (pure, testable) ---
def parse_command(text) -> dict:
   Lowercase keyword/intent matching. Return {"intent":..., "args":{...}}.
   Support at least:
     - "who is at the door" / "who's there"      -> {"intent":"who_is_there"}
     - "who was at the door" / "recent" / "history" -> {"intent":"recent"}
     - "ring" / "check the door" / "analyze"      -> {"intent":"analyze_now"}
     - "open (the) camera" / "live"               -> {"intent":"open_camera"}
     - "blind mode" / "deaf mode" / "both"        -> {"intent":"set_mode","args":{"mode":...}}
     - "how many visitors today"                  -> {"intent":"count_today"}
     - anything else                              -> {"intent":"unknown"}
   Keep it pure (no I/O) so it's unit-testable.

def handle_command(intent, *, pipeline, db, latest, access) -> str:
   Execute and RETURN a spoken-answer string (access.tts speaks it; also return
   for the UI). Examples:
     - who_is_there: grab latest frame -> pipeline.run_once -> return its
       announcement_text (this is the money command for a blind user).
     - recent: read db.recent_events(1..3) -> summarise ("Your last visitor was
       Rahul at 2:30 PM.").
     - analyze_now: same as who_is_there.
     - set_mode: access.set_mode(mode) -> "Switched to <mode> mode."
     - count_today: count today's events -> "You have had N visitors today."
     - open_camera: return "Opening the live camera." (UI reacts to a broadcast).
     - unknown: "Sorry, I did not understand that command."

--- server.py — voice endpoints ---
- POST "/listen": push-to-talk. Capture WAKEWORD_COMMAND_SECONDS of audio via
  SpeechModule, transcribe, parse_command, handle_command, SPEAK the answer,
  broadcast a {"type":"voice","text":...,"answer":...} event, return the answer.
  503 if speech unavailable. This works WITHOUT the always-on hotword.
- POST "/wakeword/{on|off}": toggle WAKEWORD_ALWAYS_ON at runtime (start/stop the
  module). GET "/wakeword_status": {available, always_on, model, threshold}.
- On wake (from the module callback): capture command -> same handle path -> speak.

--- run.py — wire wake word ---
Build WakeWordModule with on_wake = a closure that captures a command via
SpeechModule, parses, handles, and speaks (reuse the same code path as /listen).
Start it only if WAKEWORD_ALWAYS_ON. App MUST start if openwakeword is missing
(push-to-talk still available). Log the active path (always-on vs push-to-talk).

--- web UI — voice control ---
- A "🎙 Voice Command" (push-to-talk) button -> POST /listen -> show the
  recognised command + the spoken answer.
- A toggle "Always listening (Hey <wakeword>)" -> POST /wakeword/on|off, reflect
  /wakeword_status. Show a clear "listening" indicator when on.
- React to {"type":"voice"} broadcasts (show the Q/A); react to open_camera by
  scrolling to / highlighting the live video.

====================================================================
PART B — END-TO-END HARDENING (make it demo-proof)
====================================================================
1. Central status endpoint GET "/status": one JSON with EVERY module's health:
   face, vision(YOLO), antispoof(+backend/placeholder), vlm(+key count masked),
   speech(whisper/mic/silero), translate(backend), reid(+backend/placeholder),
   autoenroll, tts(engine), wakeword(available/always_on), plus config flags and
   torch version. Build a small dashboard "System Health" panel that renders it —
   green/amber/red per module. This is your DEMO SAFETY NET and a great slide.
2. Startup self-check: on boot, log a single tidy table of every module's
   available()/backend, and WARN clearly for any placeholder (anti-spoof
   heuristic, Re-ID histogram) and any missing keys — so you always know what's
   real vs stub before a demo.
3. Robustness sweep (fix anything that fails):
   - /trigger with NO camera / blank frame: must not 500 (gray-frame fallback).
   - Every module OFF (all ENABLE_* False): base app still serves, /trigger still
     creates a minimal event. Verify.
   - Long/again: rapid repeated /trigger respects the Phase-4 cooldown; no thread
     leak from speech recording (bound concurrency).
   - Errors return clean JSON, never a stack trace to the client.
4. A pytest suite tests/ covering the PURE logic (no models/network needed):
   - context_engine.infer_intent across all branches (known/unknown/spoof/parcel/
     courier/none).
   - accessibility.compose_announcement across branches (incl. translated
     transcript, reid "N times today", spoof warning).
   - voice_commands.parse_command for every supported phrase.
   - reid cosine-match logic (same vs different vectors) with synthetic vectors.
   - auto_enroll DBSCAN clustering with synthetic vectors.
   Make `pytest -q` pass. These are regression guards for the whole build.
5. README.md: a complete, current run guide — venv, system packages
   (espeak, libportaudio2, ffmpeg optional), .env keys, how to enroll, how to
   demo each feature, the torch pin note, and the "placeholders to replace before
   deployment" list (anti-spoof MiniFASNet, Re-ID OSNet, custom wake word).

====================================================================
PART C — ESP32-CAM + FLUTTER READINESS (the deploy path, documented + stubbed)
====================================================================
NO hardware is required now. Make the SWAP trivial and documented:
1. Confirm/keep the camera one-line swap: CAMERA_SOURCE = 0 (webcam) vs
   "http://<esp32-ip>:81/stream" (MJPEG). Verify the camera thread already handles
   a URL source and add reconnect/backoff if a stream drops (it may already).
2. Add POST "/ring" — a hardware webhook the ESP32 button will call: it triggers
   the SAME pipeline as the dashboard "Ring" (optionally accepts a posted JPEG
   frame in the body; if none, use the latest streamed frame). This is what the
   physical button hits later. Document the exact ESP32 HTTP call in the README.
3. docs/HARDWARE.md: the deployment guide —
   - BOM (ESP32-S3 Sense w/ mic, speaker, PIR, button, battery, enclosure; ≈₹2.7k).
   - Wiring + which ESP32 (S3-Sense has a mic; AI-Thinker CAM does NOT).
   - ESP32 responsibilities (stream MJPEG, POST /ring on button, optional PIR
     wake) vs server responsibilities (all AI). Include a minimal Arduino sketch
     OUTLINE (pseudocode) for streaming + the button POST — not a full firmware.
   - Where audio lives in deployment (phone during live session, or I2S mic).
4. docs/MOBILE.md: Flutter app plan — it consumes the SAME FastAPI backend
   (list the exact endpoints: /status, /video, /trigger, /history, /event,
   /snapshot, /mode, /reply, /listen, /suggestions, /translate). Describe Blind
   Mode (TTS + big buttons + voice) and Deaf Mode (captions + reply + flashes)
   screens. NO Flutter code required — a clear integration spec so the app is a
   thin client over the API you already have.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. torch before/after + YOLO bus.jpg sanity (MANDATORY, per pre-flight).
2. Which voice path is active: openWakeWord always-on (report model) OR
   push-to-talk fallback. Why.
3. Push-to-talk: POST /listen with a spoken/decoded command WAV
   (e.g. espeak -w q.wav "who is at the door") -> paste {command, answer} and
   confirm it SPOKE the answer. Test 3+ commands (who_is_there, recent, set_mode).
4. parse_command unit results for every supported phrase (paste the pytest
   output for that test).
5. GET /status: paste the full health JSON. Confirm the dashboard health panel
   renders it and flags placeholders (anti-spoof heuristic, Re-ID histogram) +
   missing VLM keys.
6. All-off sweep: set every ENABLE_* False, start, /trigger -> minimal event, no
   crash. Report. Then restore flags.
7. pytest -q: paste the summary (all pass).
8. /ring webhook: POST /ring (no body) -> triggers pipeline like the dashboard
   Ring; POST /ring with a JPEG body -> analyses that frame. Confirm both.
9. Non-regression: a FULL end-to-end /trigger still exercises face + YOLO REAL
   detections + anti-spoof + intent + (VLM if keys) + speech + translate + reid,
   and speaks. Conservative language preserved. Paste one final rich event JSON.
10. Confirm docs exist: README updated, docs/HARDWARE.md, docs/MOBILE.md.

====================================================================
GUARDRAILS
====================================================================
- TORCH SAFETY: no install moves torch off 2.4.1; verify YOLO after.
- Always-on listening is OPT-IN (default off) — CPU + privacy. Push-to-talk always
  works.
- Wake word / commands reuse Phase-7 SpeechModule + Phase-4 TTS — do NOT duplicate.
- parse_command stays pure/testable. handle_command is the only place with I/O.
- Every new endpoint returns clean JSON on error, never a stack trace.
- Placeholders (anti-spoof heuristic, Re-ID histogram, pretrained wake word) must
  be surfaced in /status and README as "replace before deployment".
- Do not open a camera outside accessai/camera.py. Do not rename VisitorEvent
  fields or Database methods. context_engine stays pure. Match existing style.

FIRST restate understanding + list files to create/modify. THEN build (A, then B,
then C). THEN run verification (INCLUDING torch + YOLO + pytest) and report real
output, fixing errors before finishing. This completes AccessAI — end the report
with a short "what's real vs placeholder" summary for deployment planning.
```

---

## After Phase 10, send me a final report with:
1. **torch before/after + YOLO sanity + `pytest -q` summary** (the hardening proof).
2. Voice path active (openWakeWord always-on vs push-to-talk) + 3 command results
   that spoke answers.
3. The full `GET /status` health JSON (this is your demo safety net).
4. All-off sweep result + `/ring` webhook result.
5. One final rich end-to-end event JSON exercising the whole stack.
6. Confirmation `README` + `docs/HARDWARE.md` + `docs/MOBILE.md` exist.
7. The **"what's real vs placeholder"** summary (anti-spoof, Re-ID, wake word, VLM
   keys) — your deployment-readiness checklist.

That closes the 10-phase build. When you send this final report, I'll help you
prep the demo script and the review-panel slides / synopsis if you want them.
