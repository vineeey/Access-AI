# PHASE 4 PROMPT — Accessibility Output (TTS + Blind/Deaf Modes + Two-Way Reply)

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–3 complete).

---

```
You are continuing the AccessAI project. Phases 1 (Foundation), 2 (Face
Recognition), and 3 (Object Detection + Context/Intent engine) are COMPLETE and
verified. Build ONLY Phase 4 now: the ACCESSIBILITY OUTPUT layer — spoken
announcements (Blind Mode), big-text/visual alerts (Deaf Mode), and a working
two-way reply (type -> spoken at the door). Do not build later phases.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing anything:
- config.py                  (ACCESSIBILITY_MODE, EVENT_COOLDOWN exist; add TTS)
- accessai/visitor_event.py  (announcement_text field already exists)
- accessai/context_engine.py (infer_intent + compose_interim_announcement)
- accessai/pipeline.py       (run_once currently sets ev.intent via infer_intent
                              and ev.announcement_text via compose_interim_...;
                              Pipeline.__init__ already accepts access=)
- accessai/server.py         (make_app; the /reply route currently returns 404 by
                              design; /mode get/set; broadcast; LatestFrame)
- run.py                     (module instantiation + injection)
- web/index.html, app.js, style.css (mode select + reply box already present;
                              reply currently shows "added in a later phase")

Do NOT restructure. Phase 4 ADDS two modules (TTS + accessibility engine), moves
announcement COMPOSITION into the accessibility engine, makes /reply real, and
makes the Blind/Deaf modes actually behave differently. Restate understanding in
3-4 bullets before coding.

====================================================================
TARGET ENVIRONMENT / TTS CHOICE
====================================================================
- Python 3.12, Linux, CPU-only.
- Use pyttsx3 (system TTS). On Linux pyttsx3 drives espeak, so the user must have
  espeak installed: `sudo apt install -y espeak`. If espeak/pyttsx3 is missing,
  the TTS module must DEGRADE GRACEFULLY: announcements still appear as text in
  the UI; speaking is simply skipped with a logged hint.
- Do NOT add piper-tts (no Python 3.12 wheel — this is a hard constraint).
- TTS plays on THIS machine's speakers (the laptop is the "home unit"/AI server).
  That is correct for the architecture; the door unit stays dumb.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Uncomment/add exactly:
  pyttsx3==2.98
Add a comment: pyttsx3 needs the system `espeak` package on Linux
(`sudo apt install -y espeak`); without it, TTS is skipped gracefully.

--- 2) config.py — add a TTS / Accessibility-output section ---
Keep ACCESSIBILITY_MODE and EVENT_COOLDOWN. Add:
  ENABLE_TTS = True            # master switch for spoken output
  TTS_RATE = 165               # words per minute (pyttsx3 default ~200)
  TTS_VOLUME = 1.0             # 0.0–1.0
  TTS_VOICE = ""               # "" = system default; else a pyttsx3 voice id
Note: ACCESSIBILITY_MODE ("blind"|"deaf"|"both") decides whether we speak,
show big text, or both.

--- 3) accessai/tts_module.py  (NEW) ---
A thread-safe, NON-BLOCKING TTS wrapper. pyttsx3's runAndWait() is not safe to
call re-entrantly, so use a SINGLE dedicated worker thread that owns the engine
and consumes a queue. Mirror the guarded-import + available() + logging pattern.

Guarded import:  import pyttsx3

class TTSModule:
  __init__(self, enabled=True, rate=165, volume=1.0, voice=""):
     - If not enabled or pyttsx3 missing: self._engine=None, log, return (still
       constructs fine).
     - Else: create a queue.Queue(); start ONE daemon worker thread that:
         * calls pyttsx3.init() INSIDE the worker thread (driver affinity),
         * sets rate/volume, and voice if provided,
         * loops: get text from queue; engine.say(text); engine.runAndWait().
       Wrap init in try/except; on failure set a flag so available() is False and
       speak() becomes a no-op (log once).
  available(self) -> bool: engine/worker is live.
  engine_name(self) -> str: "pyttsx3" or "none".
  speak(self, text: str) -> None:
     - If not text or not available(): return immediately.
     - Put text on the queue (non-blocking) so the request thread never blocks.
  (Optional) a small max-queue guard to drop stale announcements if flooded.

--- 4) accessai/accessibility.py  (NEW) — OWNS announcement composition now ---
This becomes the single place that turns a VisitorEvent into the final sentence
AND routes it to the right channel. It supersedes
context_engine.compose_interim_announcement (which stays as a fallback only).

  def compose_announcement(ev) -> str:
     Conservative, natural sentence built from the event. Rules:
       - Spoof (inert until P5): "Warning. A face was shown to the camera but it
         appears to be a photo."
       - Known: "<Name> is at the door."
       - Repeat unknown (ev.reid_seen_count >= 2, inert until P9): "The same
         unknown visitor has come <N> times today."
       - Multiple unknowns (visitor_count > 1): "<N> unknown visitors are at the
         door."
       - Single unknown: "An unknown visitor is at the door."
       - No one: "The doorbell rang but no one is clearly visible."
       - If carried_objects: " Carrying " + join + "."
       - If intent == "likely delivery": if ev.ocr_text (inert until P6) ->
         " Likely a delivery. Label reads: <ocr[:60]>." else " Likely a delivery."
       - If ev.scene_summary and not known (inert until P6): append it.
       - If speech (ev.translated_transcript or ev.speech_transcript, inert until
         P7): ' They said: "<...>".'
     Never say "definitely". Return the joined string (fallback "Someone is at
     the door.").

  class AccessibilityEngine:
     __init__(self, tts, mode="both"):  store tts + mode ("blind"|"deaf"|"both").
     deliver(self, ev) -> str:
        text = compose_announcement(ev); ev.announcement_text = text
        if self.mode in ("blind","both"): self.tts.speak(text)
        # Deaf/both visual delivery is handled by the server broadcasting the
        # event over WebSocket; the UI renders big text + flash + vibrate.
        return text
     set_mode(self, mode): validate + store (blind|deaf|both).
     speak_text(self, text): passthrough to tts.speak (used by /reply).

--- 5) accessai/pipeline.py — use the accessibility engine ---
Replace the Phase-3 announcement line. After infer_intent sets ev.intent/conf:
  ev.intent, ev.confidence = infer_intent(ev)
  if self.access is not None:
      self.access.deliver(ev)            # composes + speaks if blind/both
  else:
      from .context_engine import compose_interim_announcement
      ev.announcement_text = compose_interim_announcement(ev)   # fallback
Add a cooldown so repeated identical triggers don't double-speak within
config.EVENT_COOLDOWN seconds (track last spoken time + last announcement string;
if same text within cooldown, still SAVE the event but skip the tts.speak). Keep
it simple and documented. Snapshot + db.save_event + return unchanged.

--- 6) run.py — build TTS + AccessibilityEngine and inject ---
Import TTSModule, AccessibilityEngine. Build:
  tts = TTSModule(enabled=config.ENABLE_TTS, rate=config.TTS_RATE,
                  volume=config.TTS_VOLUME, voice=config.TTS_VOICE)
  access = AccessibilityEngine(tts=tts, mode=config.ACCESSIBILITY_MODE)
Pass access into Pipeline (keep face/vision args):
  pipeline = Pipeline(..., access=access)
Also pass tts + access into make_app (see next) so /reply and /mode use them.

--- 7) server.py — make /reply real; wire /mode to the engine ---
Update make_app to accept access= and tts= (keep backward-compatible defaults).
- POST "/reply" {"text": str}: 400 if empty; else access.speak_text(text)
  (or tts.speak). Return {"ok": true, "spoken": <bool available>, "engine":
  tts.engine_name(), "text": text}. REMOVE the 404-by-design behaviour.
- POST "/mode": in addition to storing the mode, call access.set_mode(mode) so
  speaking actually turns on/off live. GET "/mode" returns the current mode.
- Ensure the event broadcast on /trigger still fires so Deaf-mode UI updates.

--- 8) web UI — make the modes behave + reply work ---
- Reply box: on submit POST /reply; show a small confirmation ("Spoken at the
  door" or "TTS unavailable — text only"). Remove the old "added in a later
  phase" message.
- Deaf Mode (when mode == "deaf" or "both"): on each new event from the
  WebSocket, (a) render the announcement in LARGE text, (b) briefly flash the
  screen/card (CSS class toggle), and (c) call navigator.vibrate([200,100,200])
  if available. Blind Mode users get the spoken output from the server; the page
  need not speak in-browser.
- Keep the mode <select> working; changing it POSTs /mode.
- Vanilla JS, no CDN.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Install: source .venv/bin/activate && pip install -r requirements.txt
   Ensure espeak: sudo apt install -y espeak   (report if you couldn't).
2. Syntax: python -m py_compile on every .py; fix all errors.
3. Start: python3 run.py — confirm TTSModule reports its engine
   ("pyttsx3" or, if espeak missing, "none" with a graceful log). App MUST start
   either way.
4. Blind path: mode=both (default). Ring with a known face -> the laptop SPEAKS
   "<Name> is at the door." and the event JSON has the matching announcement_text.
   (If the sandbox has no audio device, that's fine — confirm speak() was called
   and did not raise; report the engine name and that text was queued.)
5. Deaf path: POST /mode {"mode":"deaf"} -> Ring -> confirm the UI shows big text
   + flash + (where supported) vibrate, and the server did NOT need audio.
6. Two-way reply: POST /reply {"text":"Please leave it at the gate"} ->
   {"ok":true,...}; confirm it was spoken (or gracefully text-only). Paste the
   response JSON.
7. Cooldown: fire /trigger twice within EVENT_COOLDOWN with the same result ->
   both events saved, but only the first spoke. Report what you observed.
8. Non-regression: Phases 1–3 all still behave (/video, /history, /snapshot,
   /known, /enroll, face naming, YOLO objects, intent). Conservative language
   preserved. App still starts with ENABLE_TTS=False and with mode=deaf.

====================================================================
GUARDRAILS
====================================================================
- pyttsx3 speaking must be OFF the request thread (queue + worker) so /trigger
  and /reply return fast.
- Never crash if espeak/pyttsx3 is unavailable — degrade to text-only.
- Do not open a camera outside accessai/camera.py.
- Do not rename/remove VisitorEvent fields or Database methods.
- compose_announcement is the ONE place sentences are built now; keep
  context_engine.compose_interim_announcement only as the no-access fallback.
- Match existing style (guarded imports, available(), WHY-docstrings).

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## After Phase 4, send me a report with:
1. Startup log showing the TTS engine name (pyttsx3 / none) and whether espeak
   installed.
2. A known-face `/trigger` event JSON + confirmation it spoke (or queued, if no
   audio device in the sandbox).
3. The `/reply` response JSON and whether it spoke.
4. Deaf-mode behaviour (big text / flash / vibrate) — what worked.
5. Cooldown observation (2 rapid triggers → 1 spoken).
6. Any errors + fixes; confirmation Phases 1–3 didn't regress.

Then I'll give you the **Phase 5 prompt** (Face Anti-Spoofing / Liveness) — the
security gate that stops a printed photo from being announced as a known person.
