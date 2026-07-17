# PHASE 7 PROMPT — Speech Recognition (Whisper + Silero VAD)

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–6 complete).

---

```
You are continuing the AccessAI project. Phases 1–6 are COMPLETE and verified
(Foundation, Face Recognition, Object Detection + Context/Intent, Accessibility
Output/TTS, Anti-Spoofing, VLM Scene Description + OCR). Build ONLY Phase 7 now:
SPEECH RECOGNITION — record a short audio clip on a doorbell press, gate it with
Voice Activity Detection, transcribe it offline with Whisper, and add the
transcript to the VisitorEvent + announcement + Deaf-mode caption. Do not build
later phases.

====================================================================
GOAL
====================================================================
When the doorbell is pressed (trigger), optionally capture a few seconds of audio
from the microphone, detect whether anyone actually spoke (VAD), and if so
transcribe it with Whisper (offline, CPU). The transcript joins the event so:
- Blind Mode announcement appends: ' They said: "<transcript>".'
- Deaf Mode shows the visitor's words as a caption (the visitor->text half of the
  two-way loop; the text->speech half already works from Phase 4 /reply).
Everything degrades gracefully: no mic / no audio libs / no speech => the event
proceeds exactly as Phase 6 with an empty transcript.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing:
- config.py                  (ENABLE_SPEECH flag exists; add a Speech section.
                              WHISPER_MODEL/SPEECH_SECONDS may already be present
                              from an early scaffold — reconcile, don't duplicate)
- accessai/visitor_event.py  (fields speech_transcript, language_detected ALREADY
                              EXIST; translated_transcript exists too, filled in
                              Phase 8)
- accessai/pipeline.py       (run_once(frame_bgr, trigger=...) — you will add an
                              optional audio input path; Pipeline.__init__ accepts
                              speech=, speech_enabled=)
- accessai/accessibility.py  (compose_announcement ALREADY appends
                              ' They said: "<...>"' using translated_transcript or
                              speech_transcript — inert until now)
- accessai/server.py         (POST /trigger currently grabs a frame and runs the
                              pipeline; you'll add audio capture + a manual audio
                              upload route)
- run.py                     (module instantiation + injection)

The speech_transcript plumbing into the announcement is ALREADY wired and inert.
Phase 7 builds the speech module, captures audio on trigger, and fills the field.
Restate understanding in 3-4 bullets before coding.

====================================================================
TARGET ENVIRONMENT / LIBRARY CHOICES
====================================================================
- Python 3.12, Linux, CPU-only.
- Whisper: use openai-whisper (the `whisper` pip package). Default model "base"
  is a good balance; allow "tiny" for speed. Model downloads once (~140MB base,
  ~75MB tiny) to ~/.cache/whisper.
  NOTE: openai-whisper depends on torch (already installed via ultralytics in
  Phase 3) and needs ffmpeg for some paths, but if we hand Whisper a numpy float32
  array we can AVOID the ffmpeg dependency. Prefer feeding a numpy array.
- VAD: use silero-vad (loaded via torch.hub or the `silero-vad` pip package). It
  returns speech timestamps from a 16kHz mono float32 tensor. If silero is
  unavailable, fall back to a simple energy/RMS threshold VAD so the module still
  works.
- Mic capture: use sounddevice (PortAudio). On Linux it needs the system package
  libportaudio2: `sudo apt install -y libportaudio2`. If sounddevice or a mic is
  unavailable, capture must degrade gracefully (return no audio -> empty
  transcript), and the manual /transcribe upload route (below) still lets you
  test with a WAV file.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Add pinned (CPU-friendly, known-good on 3.12):
  openai-whisper==20231117
  sounddevice==0.4.7
  silero-vad==5.1        # if this errors, load silero via torch.hub in code and
                         # drop the pip line; document what you did
Add a comment: needs system libs `ffmpeg` (optional if feeding numpy) and
`libportaudio2` for the mic (`sudo apt install -y ffmpeg libportaudio2`).

--- 2) config.py — add a Speech section (reconcile with any existing keys) ---
Keep ENABLE_SPEECH; set it True at the end of this phase. Ensure:
  SPEECH_SECONDS = 5              # how long to record after the doorbell
  SPEECH_SAMPLE_RATE = 16000      # 16 kHz mono — what Whisper + Silero expect
  WHISPER_MODEL = "base"          # tiny | base | small (bigger=slower/accurate)
  WHISPER_LANGUAGE = None         # None = auto-detect; or "en"/"hi" to force
  SPEECH_VAD = True               # gate transcription on detected speech
  SPEECH_VAD_MIN_SPEECH_SEC = 0.3 # ignore clips with less speech than this
  SPEECH_CAPTURE_ON_TRIGGER = True# auto-record on /trigger (set False to only use
                                  #   the manual /transcribe upload route)
Add comments explaining 16kHz mono and that auto-detect language feeds Phase 8.

--- 3) accessai/speech_module.py  (NEW) ---
Mirror the module pattern (guarded imports, available(), logging). Responsibilities:
audio capture, VAD gating, Whisper transcription. Keep them as separate methods so
each can be tested.

Guarded imports (each in its own try/except; set capability flags):
  import numpy as np
  import sounddevice as sd            -> self._has_mic_lib
  import whisper                      -> self._has_whisper
  silero (pip `silero_vad` OR torch.hub load) -> self._has_silero

class SpeechModule:
  __init__(self, model_name="base", sample_rate=16000, seconds=5, use_vad=True,
           vad_min_speech_sec=0.3, language=None):
     - Store params. Lazy-load Whisper on first use (don't block startup): keep
       self._model=None and load in _ensure_model() with a logged one-time
       "loading Whisper '<model>' (first run downloads ~140MB)".
     - Try to prepare Silero VAD (torch.hub.load('snakers4/silero-vad',
       'silero_vad') or the pip API). On failure, set self._has_silero=False and
       plan to use the energy fallback. Never raise.
  available(self) -> bool: self._has_whisper (transcription is the core; mic and
     VAD are optional enhancements).
  capabilities(self) -> dict: {"whisper":bool,"mic":bool,"silero":bool} for status.

  record(self, seconds=None) -> np.ndarray | None:
     - If not self._has_mic_lib: log once, return None.
     - Record `seconds` at sample_rate, mono, dtype float32 via sounddevice; use
       sd.rec + sd.wait. Return a 1-D float32 array in [-1,1]. On any error
       (no device, PortAudio) log once and return None.

  has_speech(self, audio) -> bool:
     - If audio is None/empty: False.
     - If Silero available: run it to get speech timestamps; return
       total_speech_seconds >= vad_min_speech_sec.
     - Else energy fallback: compute RMS over short windows; return True if a
       contiguous voiced region >= vad_min_speech_sec exists above an adaptive
       threshold. Keep it simple and documented.

  transcribe(self, audio) -> tuple[str, str]:
     - Returns (text, language_code). If audio None/empty or no Whisper -> ("","").
     - _ensure_model(); result = model.transcribe(audio, language=self.language,
       fp16=False)  # fp16=False for CPU. Whisper accepts a float32 numpy array at
       16kHz, avoiding ffmpeg.
     - Return (result["text"].strip(), result.get("language","")).

  listen_and_transcribe(self, seconds=None) -> tuple[str,str]:
     - audio = self.record(seconds); if audio is None -> ("","").
     - if use_vad and not has_speech(audio): log "no speech detected" -> ("","").
     - return self.transcribe(audio).

  transcribe_wav(self, wav_bytes) -> tuple[str,str]:
     - Decode WAV bytes to a 16kHz mono float32 array (use `wave` + numpy, or
       soundfile if you add it; prefer stdlib `wave` to avoid a dep). Resample if
       needed (simple linear or scipy if available). Then VAD + transcribe. This
       powers the manual upload route so you can test WITHOUT a mic.

--- 4) accessai/pipeline.py — accept audio and fill the transcript ---
Change run_once signature to accept optional audio:
   run_once(self, frame_bgr, trigger="manual", audio=None)
Add a speech step AFTER the VLM step (Phase 6) and BEFORE infer_intent:

  # --- Speech recognition (Phase 7) ---
  if self.speech_enabled and self.speech is not None and self.speech.available():
      text, lang = "", ""
      if audio is not None:
          # audio already captured (e.g., uploaded WAV decoded to np array)
          if (not self.speech.use_vad) or self.speech.has_speech(audio):
              text, lang = self.speech.transcribe(audio)
      elif config.SPEECH_CAPTURE_ON_TRIGGER:
          text, lang = self.speech.listen_and_transcribe()
      ev.speech_transcript = text or ""
      ev.language_detected = lang or ""

  # infer_intent + access.deliver already append the transcript to the
  # announcement (' They said: "..."'). No change needed there.

Keep everything else unchanged. Snapshot + db.save_event + return unchanged.
NOTE ON BLOCKING: recording adds ~SPEECH_SECONDS of latency to /trigger. That's
acceptable for a doorbell, but the server route should run the pipeline in the
executor (it already does). Document that the announcement now arrives after the
recording window.

--- 5) run.py — instantiate + inject SpeechModule ---
Import SpeechModule. Build:
  speech = None
  if config.ENABLE_SPEECH:
      speech = SpeechModule(model_name=config.WHISPER_MODEL,
                            sample_rate=config.SPEECH_SAMPLE_RATE,
                            seconds=config.SPEECH_SECONDS,
                            use_vad=config.SPEECH_VAD,
                            vad_min_speech_sec=config.SPEECH_VAD_MIN_SPEECH_SEC,
                            language=config.WHISPER_LANGUAGE)
Pass into Pipeline: speech=, speech_enabled=config.ENABLE_SPEECH.
Log capabilities (whisper/mic/silero) on startup. App MUST start if speech libs
are missing (whisper=False => speech disabled, everything else works).

--- 6) server.py — capture path + manual upload + status ---
- POST "/trigger": unchanged interface, but the pipeline now auto-records when
  SPEECH_CAPTURE_ON_TRIGGER is True and speech is enabled. (No body change.)
- POST "/transcribe": accept a multipart file upload (a .wav). Decode -> call
  pipeline.speech.transcribe_wav(bytes) -> return {"text","language"}. 503 if
  speech unavailable. This lets you TEST transcription without a mic.
- GET "/speech_status": return pipeline.speech.capabilities() + enabled flag +
  model name, or {"enabled":false} if none.
- Ensure the event broadcast still fires so the Deaf-mode caption updates.

--- 7) web UI — show the visitor's words (Deaf caption) ---
- Current Visitor card: add a "🗣 Visitor said" line rendering
  ev.speech_transcript (and language if present). Prominent in Deaf mode (this is
  the caption that closes the visitor->text half of the loop).
- The existing Reply box (Phase 4) already does text->speech; keep it. Together
  they are the two-way conversation.
- Optional: a small "🎙 Listening… (5s)" hint shown after Ring while recording.
- Status pill: "Speech: on (base, mic✓ vad✓)" from /speech_status. Vanilla JS.

--- 8) Flip the flag ---
Set ENABLE_SPEECH = True in config.py.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Install: pip install -r requirements.txt. Report if you needed
   `sudo apt install -y ffmpeg libportaudio2`.
2. Syntax: python -m py_compile on every .py; fix all errors.
3. Start: python3 run.py — confirm SpeechModule logs capabilities
   (whisper/mic/silero) and the app starts. App MUST start with speech libs
   missing (graceful).
4. Manual transcription (works without a mic): POST a short WAV of someone saying
   e.g. "I have a package for you" to /transcribe -> paste {"text","language"}.
   If you have no sample WAV, synthesize one (e.g. via espeak: `espeak -w
   test.wav "I have a package for you"`) and transcribe THAT — report the text.
5. Trigger-with-audio path: if a mic exists, Ring and speak -> event
   speech_transcript populated, announcement ends with ' They said: "...".',
   Deaf caption shows the words. If NO mic in the sandbox, prove the pipeline
   deterministically by passing a decoded WAV array as run_once(audio=...) and
   show speech_transcript filled + announcement updated. SAY which you did.
6. VAD gate: a silent/near-silent clip -> has_speech False -> empty transcript,
   event still completes. Report.
7. Known-face + speech: a known visitor who speaks -> "<Name> is at the door.
   They said: '...'." (VLM still skipped for known; speech still runs.) Confirm.
8. Non-regression: Phases 1–6 all behave (face, YOLO, intent, TTS, /reply, /mode,
   anti-spoof, VLM-for-unknown, /vlm_status). Conservative language preserved.

====================================================================
GUARDRAILS
====================================================================
- Feed Whisper a 16kHz mono float32 numpy array to AVOID the ffmpeg dependency;
  fp16=False on CPU.
- Lazy-load the Whisper model (don't block server startup on the download).
- No mic / no libs / no speech => empty transcript, event proceeds (graceful).
- VAD prevents transcribing silence (saves CPU + avoids hallucinated text — Whisper
  can invent words from noise, so the VAD gate matters).
- Recording blocks for SPEECH_SECONDS; keep the pipeline call in the executor.
- Do not open the CAMERA anywhere but accessai/camera.py (audio is separate).
- Do not rename VisitorEvent fields or Database methods. Match existing style.
- language_detected must be filled from Whisper — Phase 8 (translation) depends on it.

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## System packages you may need first (run on your machine):
```
sudo apt install -y ffmpeg libportaudio2
```
`libportaudio2` is for the mic (sounddevice); `ffmpeg` is a safety net (the module
is written to avoid needing it by feeding Whisper a numpy array).

## After Phase 7, send me a report with:
1. Startup log showing speech capabilities (whisper / mic / silero) + Whisper model.
2. `/transcribe` result on a WAV (the espeak-generated one is fine) — the text.
3. A `/trigger` (or deterministic audio-array) event JSON with `speech_transcript`
   + `language_detected` filled and the announcement ending in `They said: "..."`.
4. VAD gate result (silent clip → empty transcript, event still completes).
5. Whether you used a real mic or a decoded WAV/array (method honesty).
6. Any errors + fixes; confirmation Phases 1–6 didn't regress.

Then I'll give you the **Phase 8 prompt** (Multi-language + Translation), which
takes `language_detected` and translates the transcript into the user's language
for the announcement and subtitle.
