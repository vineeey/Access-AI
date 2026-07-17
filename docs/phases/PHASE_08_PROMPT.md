# PHASE 8 PROMPT — Multi-language + Translation

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–7 complete).

---

```
You are continuing the AccessAI project. Phases 1–7 are COMPLETE and verified
(Foundation, Face Recognition, Object Detection + Context/Intent, Accessibility
Output/TTS, Anti-Spoofing, VLM Scene Description + OCR, Speech Recognition). Build
ONLY Phase 8 now: MULTI-LANGUAGE + TRANSLATION. Do not build later phases.

====================================================================
CRITICAL PRE-FLIGHT — PROTECT THE TORCH VERSION (read first)
====================================================================
The ML stack is on a PINNED, WORKING torch trio:
  torch==2.4.1  torchvision==0.19.1  torchaudio==2.4.1
In Phase 7, installing an ML package silently downgraded torch and BROKE YOLO
(predict() returned 0 detections with NO error — a silent regression). You MUST
NOT let that happen again.

Rules for ANY pip install in this phase:
- Before installing, record the current versions:
    python -c "import torch,torchvision; print(torch.__version__, torchvision.__version__)"
- Prefer translation approaches that DO NOT move torch. If a package wants to
  change torch/torchvision/torchaudio, STOP and either (a) pin them explicitly in
  the same install command, or (b) choose a lighter approach that avoids torch.
- AFTER installing, re-verify BOTH:
    1. torch is still 2.4.1 (reinstall the trio if it moved).
    2. YOLO still detects: run predict on the bundled bus.jpg and confirm it finds
       a bus + multiple persons (NOT zero detections).
- Report the before/after torch versions and the YOLO sanity check in your report.

====================================================================
GOAL
====================================================================
The visitor's transcript (from Phase 7 Whisper, with language_detected) may be in
a language the user doesn't speak. Translate it into the user's chosen language so:
- Blind Mode announcement speaks the transcript in the USER'S language.
- Deaf Mode shows a subtitle in the user's language (with the original available).
Also translate the whole announcement if needed. Everything degrades gracefully:
no translator / same language / failure => use the original transcript unchanged.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing:
- config.py                  (USER_LANGUAGE exists; ENABLE_TRANSLATE flag exists;
                              WHISPER_LANGUAGE; add a Translation section)
- accessai/visitor_event.py  (fields language_detected AND translated_transcript
                              ALREADY EXIST)
- accessai/speech_module.py  (transcribe returns (text, language_code))
- accessai/pipeline.py       (Phase-7 speech step fills speech_transcript +
                              language_detected; Pipeline.__init__ accepts
                              translate=, translate_enabled=)
- accessai/accessibility.py  (compose_announcement ALREADY prefers
                              translated_transcript over speech_transcript for the
                              ' They said: "..."' clause — inert until now)
- accessai/tts_module.py     (pyttsx3; note: espeak CAN speak some non-English via
                              voice/language codes, but quality varies — see TTS
                              section below)
- run.py                     (module instantiation + injection)

The translated_transcript plumbing into the announcement is ALREADY wired and
inert (accessibility prefers it when present). Phase 8 builds the translator and
fills that field. Restate understanding in 3-4 bullets before coding.

====================================================================
TRANSLATION APPROACH — choose the most robust, torch-safe option
====================================================================
The user's context: India, multilingual (Hindi, Malayalam, Tamil, etc.), wants
strong Indian-language support, prefers free/local but has a GitHub Models API key
setup from Phase 6. Implement in THIS priority order and REPORT which you used:

  OPTION A (preferred — reuse the Phase 6 GitHub Models VLM keys for TEXT
    translation): the same OpenAI-compatible chat endpoint can translate text.
    Add a translate() call that sends a text-only chat request:
      system: "You are a translation engine. Translate the user's text into
               <TARGET_LANG_NAME>. Output ONLY the translation, no notes."
      user: the transcript.
    This needs NO new heavy dependency, does NOT touch torch, and reuses the
    existing multi-key failover. This is the SAFEST option for the torch issue.
    Downside: needs network + keys. Handle unavailability by falling back to the
    original text (graceful).

  OPTION B (offline, local — only if it does NOT disturb torch): a lightweight
    local MT. NLLB-200-distilled-600M via transformers, OR IndicTrans2, are strong
    for Indian languages but are HEAVY and pull torch/transformers — HIGH RISK of
    moving torch. If you attempt this, you MUST pin torch and re-verify YOLO after.
    Given the risk, DO NOT default to this; only use it if the user explicitly
    wants fully-offline translation and you can prove torch stayed 2.4.1.

  OPTION C (fallback stub): if neither is available (no keys, no offline model),
    translate() returns the original text unchanged and language_detected is still
    recorded, so the system is honest ("could not translate, showing original").

Default: OPTION A (GitHub Models text translation), because it's torch-safe and
reuses existing infra. Make the backend configurable.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) config.py — add a Translation section ---
Keep USER_LANGUAGE, ENABLE_TRANSLATE. Set ENABLE_TRANSLATE True at end of phase.
Add:
  USER_LANGUAGE = "en"              # target language code the user wants to hear
  TRANSLATE_BACKEND = "github"      # "github" (Option A) | "local" (B) | "none" (C)
  # human-readable names for prompts + a small code->name map:
  LANGUAGE_NAMES = {"en":"English","hi":"Hindi","ml":"Malayalam","ta":"Tamil",
                    "te":"Telugu","kn":"Kannada","bn":"Bengali","mr":"Marathi",
                    "gu":"Gujarati","pa":"Punjabi","ur":"Urdu"}
  TRANSLATE_ANNOUNCEMENT = False    # if True, translate the WHOLE announcement,
                                    #   not just the visitor's transcript
Add a comment: USER_LANGUAGE is what the blind/deaf user consumes; the visitor may
speak anything (language_detected from Whisper). Translate visitor->user.

--- 2) accessai/translate_module.py  (NEW) ---
Mirror the module pattern (guarded imports, available(), logging).

class TranslateModule:
  __init__(self, backend="github", user_language="en", language_names=None,
           vlm=None):
     - Store target lang + names. For backend "github": REUSE the Phase-6
       VLMModule instance (pass it in from run.py) — do NOT create new keys. Set
       available based on vlm.available(). For "local": lazy-load the MT model on
       first use (and follow the torch-safety rules). For "none": always a
       passthrough.
  available(self) -> bool: backend can actually translate (github: vlm available;
     local: model loadable; none: False but passthrough still works).
  backend_name(self) -> str.

  translate(self, text, src_lang="", target_lang=None) -> str:
     - target = target_lang or self.user_language.
     - If text empty -> "".
     - If src_lang and src_lang == target -> return text unchanged (no API call —
       saves quota; also covers English->English).
     - backend "github": call the VLM's text-chat translate helper (add a
       translate_text(text, target_name) method to VLMModule that does a text-only
       chat completion using the SAME failover loop; target_name from
       language_names). On failure -> return text unchanged (graceful).
     - backend "local": run the MT model; on failure -> text unchanged.
     - backend "none": return text unchanged.
     Never raise; always return a string.

--- 3) accessai/vlm_module.py — add a text-only translate helper ---
Add:
  def translate_text(self, text, target_language_name) -> str:
     Uses the existing _chat/failover machinery but with NO image — a text-only
     messages payload:
       system: "You are a translation engine. Translate the user's message into
                {target_language_name}. Output ONLY the translated text."
       user: text
     Return the translation on ok, else "" (caller falls back to original).
  (Ensure _chat can handle a None/absent image gracefully — if the current _chat
   always attaches an image, add a text-only branch or a small _chat_text method.)

--- 4) accessai/pipeline.py — translate the transcript ---
AFTER the Phase-7 speech step (which sets ev.speech_transcript +
ev.language_detected) and BEFORE infer_intent / access.deliver, insert:

  # --- Translation (Phase 8) ---
  if (self.translate_enabled and self.translate is not None
          and ev.speech_transcript):
      src = ev.language_detected or ""
      target = config.USER_LANGUAGE
      if src != target:
          translated = self.translate.translate(ev.speech_transcript,
                                                 src_lang=src, target_lang=target)
          # Only store if it actually changed / succeeded:
          if translated and translated.strip() and translated.strip() != ev.speech_transcript.strip():
              ev.translated_transcript = translated

  # accessibility.compose_announcement already prefers translated_transcript for
  # the ' They said: "..."' clause. If TRANSLATE_ANNOUNCEMENT is True, optionally
  # translate the FULL announcement AFTER access.deliver sets it (see below).

If config.TRANSLATE_ANNOUNCEMENT is True: after access.deliver(ev) has composed
ev.announcement_text, translate the whole announcement into USER_LANGUAGE and
re-speak it. Keep this behind the flag (default False) to avoid double-speaking;
document the behaviour. Snapshot + db.save_event + return unchanged.

--- 5) run.py — build TranslateModule (reuse the VLM) + inject ---
After building `vlm` (Phase 6), build:
  translate = None
  if config.ENABLE_TRANSLATE:
      translate = TranslateModule(backend=config.TRANSLATE_BACKEND,
                                  user_language=config.USER_LANGUAGE,
                                  language_names=config.LANGUAGE_NAMES,
                                  vlm=vlm)   # reuse Phase-6 keys, torch-safe
Pass into Pipeline: translate=, translate_enabled=config.ENABLE_TRANSLATE.
Log the backend + target language. App MUST start if translation is unavailable
(passthrough).

--- 6) server.py — status + a manual translate test route ---
- GET "/translate_status": {enabled, backend, available, user_language}.
- POST "/translate" {"text":..., "src":"hi", "target":"en"}: returns
  {"translated": ...} using pipeline.translate. Lets you test without speech.
- Keep the event broadcast so the Deaf subtitle updates.

--- 7) web UI — show original + translated ---
- Current Visitor card: if translated_transcript present, show BOTH:
    "🗣 Visitor said (hi): <original>"
    "🌐 Translated (en): <translated>"
  If no translation, show just the original as in Phase 7.
- A USER_LANGUAGE selector in settings that POSTs to a small route to change the
  target language live (optional but nice): add POST "/user_language" {"lang"} ->
  updates config in memory + translate.user_language. Reflect in /translate_status.
- Status pill: "Translate: on (github → en)". Vanilla JS.

--- 8) Flip the flag ---
Set ENABLE_TRANSLATE = True in config.py.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. PRE-FLIGHT: record torch/torchvision versions BEFORE any install.
2. Install deps (Option A adds NOTHING new — it reuses requests from Phase 6). If
   you attempt Option B, pin torch and follow the safety rules.
3. POST-INSTALL: confirm torch is STILL 2.4.1 and run the YOLO bus.jpg sanity
   check (bus + persons detected, not zero). Report both. THIS IS MANDATORY.
4. Syntax: python -m py_compile on every .py; fix all errors.
5. Start: python3 run.py — confirm TranslateModule logs backend + target lang and
   /translate_status works. App MUST start with translation unavailable.
6. Manual translate: POST /translate {"text":"मेरे पास आपके लिए एक पैकेज है",
   "src":"hi","target":"en"} -> expect an English translation (or, if no keys in
   the sandbox, the graceful passthrough returning the original — SAY which).
   Paste the response.
7. End-to-end: feed a Hindi speech WAV (e.g. espeak -v hi, or any Hindi sample)
   through the speech+translate path -> event has language_detected="hi",
   speech_transcript in Hindi, translated_transcript in English, and the
   announcement's 'They said: "..."' uses the ENGLISH translation. Paste the
   event JSON. If no API keys/network in the sandbox, prove it deterministically
   by stubbing VLM.translate_text to return a canned translation and SAY so.
8. Same-language no-op: src == target -> NO API call, translated_transcript stays
   empty, original used. Confirm (quota-saving path).
9. Non-regression: Phases 1–7 all behave (face, YOLO REAL detections, intent, TTS,
   /reply, /mode, anti-spoof, VLM-for-unknown, speech transcript). Conservative
   language preserved.

====================================================================
GUARDRAILS
====================================================================
- TORCH SAFETY IS PARAMOUNT: do not let any install move torch off 2.4.1; verify
  YOLO after. This is the #1 risk this phase.
- Default to Option A (GitHub Models text translation) — torch-safe, reuses keys.
- Same-language => no API call (save quota). Failure => original text (graceful).
- Never raise from translate(); always return a string.
- Reuse the Phase-6 VLMModule + its multi-key failover; do NOT create new keys.
- Do not rename VisitorEvent fields or Database methods. context_engine stays pure.
- Do not open a camera outside accessai/camera.py. Match existing style.

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification (INCLUDING the torch + YOLO sanity check) and report real output,
fixing errors before finishing.
```

---

## After Phase 8, send me a report with:
1. **torch before/after + YOLO bus.jpg sanity check** (the mandatory torch-safety
   proof — I want to see torch still 2.4.1 and YOLO still detecting).
2. Which translation backend loaded (A GitHub Models / B local / C passthrough)
   and why.
3. `/translate` manual result (Hindi→English, or graceful passthrough if no keys).
4. End-to-end event JSON: `language_detected="hi"`, Hindi `speech_transcript`,
   English `translated_transcript`, announcement using the translation.
5. Same-language no-op confirmation (no API call).
6. Method honesty (real API vs stubbed) + any errors + fixes; Phases 1–7
   non-regression.

Then I'll give you the **Phase 9 prompt** (Visitor Re-ID + Auto-Enrollment) — the
memory layer: "the same unknown visitor has come 3 times today" and "save this
frequent visitor?".
