# PHASE 12 PROMPT — Speed Up + Doorbell/Voice Separation + Richer Unknown Description

A tuning phase after the natural-voice upgrade. Fixes three real issues found in
live use: (1) the doorbell takes 7–10s, (2) the doorbell should NOT record audio —
only a dedicated button should, (3) unknown-visitor descriptions are too thin
(need age, gender, clothing, carried objects). Paste EVERYTHING in the fenced
block below as your next message to the Claude agent in VS Code.

---

```
You are tuning the completed AccessAI project (Phases 1–11 done, working). Build
ONLY these three improvements. Do NOT add unrelated features. Do NOT break any
existing behaviour.

  ISSUE 1 (SPEED): a doorbell press takes 7–10 seconds. Make it fast (target: a
     KNOWN face announces in under ~3s; an UNKNOWN visitor in under ~5s).
  ISSUE 2 (UX): the doorbell must NOT record the visitor's voice. Audio should be
     captured ONLY when a dedicated button is pressed (two-way communication).
  ISSUE 3 (RICHNESS): an unknown visitor's description is too thin. It must
     include approximate AGE, GENDER, CLOTHING (type + colour), any UNIFORM, and
     CARRIED OBJECTS — conservatively phrased.

====================================================================
TORCH SAFETY (still applies — but no new installs needed here)
====================================================================
The pinned stack is torch==2.4.1 / torchvision==0.19.1 / torchaudio==2.4.1,
numpy 1.26.4, onnxruntime 1.18.1. NONE of these changes require a new pip install
(age/gender uses a model ALREADY in the InsightFace buffalo_l pack). If you find
yourself installing anything, STOP — you probably don't need to. If you must,
verify torch is still 2.4.1 and YOLO bus.jpg still detects (bus + persons) after.

====================================================================
STEP 0 — READ CURRENT CODE FIRST
====================================================================
Read fully before changing:
- config.py                  (SPEECH_CAPTURE_ON_TRIGGER, SPEECH_SECONDS,
                              VLM_* , WHISPER_MODEL; add a few keys)
- accessai/pipeline.py       (run_once(frame, trigger, audio=None) — the perception
                              order: face -> antispoof -> vision -> vlm -> speech ->
                              translate -> reid; this is where speed + richness live)
- accessai/face_module.py    (FaceModule uses FaceAnalysis with
                              allowed_modules=["detection","recognition"] — this is
                              why genderage is IGNORED; we will re-enable it)
- accessai/vision_module.py  (YOLO detect)
- accessai/vlm_module.py     (describe_scene / describe_and_read prompt — make it
                              richer; keep the failover + combined-call design)
- accessai/visitor_event.py  (add age/gender fields — do NOT rename existing ones)
- accessai/context_engine.py (compose... lives in accessibility; infer_intent pure)
- accessai/accessibility.py  (compose_announcement — extend the unknown branch)
- accessai/server.py         (/trigger; add a dedicated visitor-listen route)
- web/index.html, app.js, style.css (button changes)
Restate understanding in 3-4 bullets before coding.

====================================================================
FIX 1 — SEPARATE THE DOORBELL FROM VOICE RECORDING (fixes speed + UX)
====================================================================
The single biggest latency cause is that /trigger records ~5s of audio every
press. Remove audio from the doorbell path entirely.

--- config.py ---
  SPEECH_CAPTURE_ON_TRIGGER = False   # doorbell NEVER records audio now
  VISITOR_LISTEN_SECONDS = 6          # duration when the dedicated button is used
  # (keep SPEECH_SECONDS for the blind user's voice commands / wake word)

--- accessai/pipeline.py ---
run_once must NOT record audio on a doorbell trigger. Ensure the speech step only
runs when `audio` is explicitly passed in (i.e. from the dedicated listen route),
never auto-recorded here. Concretely: DELETE / disable the
`elif config.SPEECH_CAPTURE_ON_TRIGGER: listen_and_transcribe()` branch so a
normal /trigger does no audio work at all. speech_transcript stays "" on a plain
doorbell press.

--- accessai/server.py ---
Add a DEDICATED route for two-way communication (visitor -> text), separate from
the doorbell and separate from the blind user's /listen voice-commands:
  POST "/hear_visitor":
    - Records VISITOR_LISTEN_SECONDS via SpeechModule, runs VAD, transcribes with
      Whisper, and (Phase 8) translates into USER_LANGUAGE.
    - Attaches the transcript to the MOST RECENT event (update it in memory + DB)
      OR returns it as a standalone {transcript, translated, language}.
    - Speaks/broadcasts so Deaf-mode caption + Blind-mode announcement update:
      e.g. broadcast {"type":"visitor_speech", "text":..., "translated":...}.
    - 503 if speech unavailable. Clean JSON on error, never a stack trace.
  Keep the existing /listen (blind user's voice COMMANDS) unchanged — it is a
  DIFFERENT feature from /hear_visitor (visitor's SPEECH).

--- web UI ---
Make the three audio/action buttons clearly distinct and labelled:
  🔔 "Ring Doorbell"      -> POST /trigger  (visual only, FAST, no recording)
  🎤 "Hear Visitor"       -> POST /hear_visitor (records the visitor to caption/
                             translate — the two-way comm, visitor side)
  🎙 "Voice Command"      -> POST /listen (blind user commands the system)
Show a "🎤 Listening to visitor… (6s)" indicator only for Hear Visitor. The
doorbell button must feel instant — no listening indicator.

====================================================================
FIX 2 — MAKE THE PIPELINE FAST
====================================================================
--- accessai/pipeline.py — parallelise independent perception ---
Face recognition (InsightFace) and object detection (YOLO) are INDEPENDENT and
both release the GIL during native inference, so run them CONCURRENTLY:
  - Use a concurrent.futures.ThreadPoolExecutor(max_workers=2): submit
    face.identify(frame) and vision.detect(frame) together, then gather both.
  - Anti-spoof depends on the face box, so run it AFTER face returns.
  - VLM depends on identity (unknown only), so it stays after.
Keep everything guarded; if either module is disabled/unavailable, just skip it
(don't submit it). Document the concurrency.

--- VLM responsiveness ---
- Lower VLM_TIMEOUT to 12 (from 20) so a slow API call can't stall the
  announcement for long. Keep the multi-key failover.
- Keep the SINGLE combined VLM call (scene + labels + attributes) — one network
  round trip, not three.
- OPTIONAL but recommended (config flag VLM_ASYNC_ENRICH, default True): for an
  UNKNOWN visitor, SPEAK the fast local announcement immediately (face age/gender
  + YOLO objects + intent), then run the VLM in a background thread and, when it
  returns, UPDATE the stored event + dashboard card + history with the richer
  scene description (do NOT re-speak by default). This makes the doorbell feel
  instant even for unknowns while still enriching the record. If you implement
  this, guard it carefully so a late VLM result updates the RIGHT event id and
  never blocks. If it adds risk, keep it behind the flag OFF and just rely on the
  lower timeout — your call, but document what you did.

--- Whisper (only affects /hear_visitor now, not the doorbell) ---
Leave WHISPER_MODEL="base"; note "tiny" is available for faster visitor
transcription. The doorbell no longer touches Whisper at all.

Report the measured /trigger latency BEFORE and AFTER for a known face and an
unknown visitor.

====================================================================
FIX 3 — RICHER UNKNOWN-VISITOR DESCRIPTION (age, gender, clothing, objects)
====================================================================
Two complementary sources: (a) InsightFace age/gender (LOCAL, instant, free — the
model is already in buffalo_l), and (b) a richer VLM prompt for appearance.

--- accessai/face_module.py — re-enable age + gender ---
Change the FaceAnalysis construction to ALSO load the genderage module. Either:
  FaceAnalysis(name=model_name, allowed_modules=["detection","recognition","genderage"])
or drop allowed_modules so the full pack loads. Then each detected face exposes
`.age` (int) and `.sex` ("M"/"F"). Extend identify() results (and
embed_largest_face if useful) to include age + gender for the largest face,
WITHOUT breaking the existing return keys (add new keys, keep old ones).
NOTE: InsightFace age is approximate (±several years) — never present it as exact.

--- accessai/visitor_event.py — add fields (do NOT rename existing) ---
Add: age: int | None = None
     gender: str = ""            # "man"/"woman"/"" — map M->man, F->woman
     appearance: str = ""        # short VLM appearance line (clothing/uniform)
(scene_summary can remain for the broader scene; appearance is the person-focused
line. Or reuse scene_summary — but a dedicated field is cleaner.)

--- accessai/pipeline.py — populate age/gender ---
When face results exist (known OR unknown), copy the largest face's age/gender
into ev.age / ev.gender. Bucket age into a CONSERVATIVE phrase later (in
accessibility), not exact.

--- accessai/vlm_module.py — richer prompt (UNKNOWN only) ---
Update the combined describe_and_read system/user prompt to request, in ONE short
JSON or a compact sentence:
  - approximate age range (e.g. "20s", "middle-aged") — cautious
  - gender presentation (man/woman/unsure)
  - clothing: type + main colours (e.g. "blue shirt, dark trousers")
  - any uniform / company branding (e.g. "courier uniform")
  - carried objects (bag, parcel, documents, tools…)
  - overall one-line scene summary
  - visible label/courier text (OCR) as before
Keep it CONSERVATIVE ("appears to be", "looks like"), never "definitely". Parse
defensively; on any failure fall back to "". Put the appearance line into
ev.appearance and keep ocr_text/scene_summary as today.

--- accessai/accessibility.py — richer unknown announcement ---
Extend the UNKNOWN branch of compose_announcement to weave in what's available,
conservatively. Build the age phrase from ev.age as a RANGE, not a number:
   age<13 "a child" ; 13–19 "a teenager" ; 20–29 "in their twenties" ;
   30–39 "in their thirties" ; 40–49 "in their forties" ; 50–64 "middle-aged" ;
   65+ "elderly" ; unknown -> omit.
Example outputs (only include parts that exist):
   "An unknown visitor is at the door — a man in his thirties, wearing a blue
    shirt, carrying a backpack. Likely a delivery. Label reads: BlueDart."
   "An unknown visitor is at the door — a woman, appears to be in her twenties."
Order: who/age/gender -> appearance (clothing/uniform) -> carried objects ->
intent/delivery -> label -> (visitor speech if any). Keep it to 1–2 natural
sentences. Never fabricate details not present. KNOWN visitors keep their simple
"<Name> is at the door." (optionally + carried objects) — do NOT add age/gender
for known people (we know who they are).

--- web UI — show the richer details ---
On the Current Visitor card for unknowns, show age/gender + appearance + carried
objects + label as small labelled lines. History too (truncated). Vanilla JS.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Torch/numpy/onnxruntime unchanged (no install expected) + YOLO bus.jpg still
   detects. Confirm.
2. SPEED: measure and report /trigger wall-clock BEFORE (record it first if you
   can, else state prior ~7–10s) and AFTER, for (a) a known face and (b) an
   unknown visitor. Target known < ~3s, unknown < ~5s (or instant local + async
   VLM enrich). Show the numbers.
3. NO doorbell recording: confirm a /trigger does ZERO audio work
   (speech_transcript stays "", no "listening" delay, logs show no recording).
4. Dedicated listen: POST /hear_visitor with speech present -> transcript (+
   translation) attaches/returns and is spoken/captioned. With silence -> VAD
   gates it, empty, no crash. Paste results. Confirm /listen (voice commands) and
   /hear_visitor (visitor speech) are separate and both work.
5. RICHNESS: an UNKNOWN visitor event -> paste the JSON showing age, gender,
   appearance (clothing/uniform), carried_objects, and the final announcement
   reading naturally like the examples. Show that age is a RANGE phrase, not a
   raw number, in the announcement. A KNOWN visitor -> confirm no age/gender is
   announced (still "<Name> is at the door.").
   (If you can't pose live, use archived/sample person images and SAY which — as
    in prior phases. InsightFace age/gender will run on any real face image.)
6. Non-regression: face naming, anti-spoof downgrade, intent, TTS (Kokoro natural
   voice), /reply, /mode, /status, Deaf mode, translation all still behave.
   Conservative language preserved.

====================================================================
GUARDRAILS
====================================================================
- No new pip installs expected; if any, keep torch 2.4.1 + verify YOLO.
- The doorbell (/trigger) does NO audio recording — ever. Audio is ONLY via
  /hear_visitor (visitor) and /listen (blind user's commands).
- Parallelise ONLY independent steps (face ∥ YOLO); keep dependent steps ordered.
- Age/gender: LOCAL InsightFace for speed; VLM adds clothing/appearance for
  unknowns only. Never show age for KNOWN people. Age is always a RANGE, never
  exact. Conservative phrasing throughout — no "definitely".
- Keep the non-blocking TTS worker + queue. Keep graceful degradation everywhere
  (no key -> local age/gender + YOLO still give a decent description).
- Do not rename VisitorEvent fields or DB methods (ADD fields only). context_engine
  stays pure. Camera only via accessai/camera.py. Match existing style.

FIRST restate understanding + list files to modify. THEN build. THEN run
verification (INCLUDING before/after latency numbers) and report real output,
fixing errors before finishing.
```

---

## After it's done, send me a report with:
1. **Before/after `/trigger` latency** for a known face and an unknown visitor
   (the speed proof).
2. Confirmation the doorbell does zero audio recording, and that `/hear_visitor`
   (visitor speech) vs `/listen` (blind user commands) are separate + working.
3. An **unknown-visitor event JSON** with `age`, `gender`, `appearance`,
   `carried_objects`, and the natural richer announcement (age as a *range*).
4. Confirmation a **known** visitor still just says "<Name> is at the door." (no
   age/gender).
5. Torch/numpy/onnxruntime unchanged + YOLO still detecting; Phases 1–11
   non-regression.

## Note on accuracy (your "not accurate" point)
Two of your modules are still the **demo placeholders** we flagged — and they're
the ones most likely to feel "off":
- **Anti-spoof** = the Laplacian heuristic (can misjudge real vs photo).
- **Re-ID** = HSV colour histogram (keys on clothing colour, so it can confuse
  two people in similar clothes).

Those aren't tuning bugs — they're the placeholders awaiting real models
(MiniFASNet `.onnx` → `models/antispoof/`, OSNet `.onnx` → `models/reid/`), each a
zero-code drop-in. This Phase 12 makes the description + speed genuinely good; if
anti-spoof/re-ID accuracy matters for your demo, tell me and I'll write a small
"drop in the real models" prompt next. Face recognition accuracy itself can also
be tuned via `FACE_MATCH_THRESHOLD` — say the word if it's mis-naming people.
