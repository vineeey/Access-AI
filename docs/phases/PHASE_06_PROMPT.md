# PHASE 6 PROMPT — VLM Scene Description + OCR (GitHub Models, key failover)

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–5 complete).

---

```
You are continuing the AccessAI project. Phases 1–5 are COMPLETE and verified
(Foundation, Face Recognition, Object Detection + Context/Intent, Accessibility
Output/TTS, Anti-Spoofing). Build ONLY Phase 6 now: VLM SCENE DESCRIPTION + OCR
on labels, using a cloud vision model via GitHub Models, with automatic failover
across multiple API keys. Do not build later phases.

====================================================================
GOAL
====================================================================
For UNKNOWN visitors, call a cloud vision-language model to (a) produce a short,
conservative natural-language scene description and (b) read any visible label
text (courier name / parcel label / ID). Feed both into the VisitorEvent so the
context engine and announcement get richer ("Likely a delivery. Label reads:
BlueDart."). KNOWN visitors SKIP the VLM entirely (latency win — this is a core
design rule from Phase 1). Everything must degrade gracefully to the Phase-3
YOLO-only description if the VLM is unavailable.

====================================================================
PROVIDER — GitHub Models (OpenAI-compatible)
====================================================================
GitHub Models exposes an OpenAI-compatible Chat Completions API with vision
support. Details you must implement against:
- Base URL: https://models.github.ai/inference
  (also accept the legacy https://models.inference.ai.azure.com via config)
- Auth: HTTP header  Authorization: Bearer <GITHUB_PAT>
- Endpoint: POST {base}/chat/completions
- Body: OpenAI chat format with an image passed as a data URL in the message
  content, e.g.:
    {
      "model": "<model>",
      "messages": [
        {"role":"system","content":"<instruction>"},
        {"role":"user","content":[
          {"type":"text","text":"<prompt>"},
          {"type":"image_url","image_url":{"url":"data:image/jpeg;base64,<...>"}}
        ]}
      ],
      "temperature": 0.2,
      "max_tokens": 300
    }
- Vision-capable model names to try (configurable): "gpt-4o-mini" (default,
  cheap/fast), "gpt-4o", "openai/gpt-4o-mini" (some deployments namespace the
  model). Make the model name a config value; if a 404/unknown-model error comes
  back, that's a config problem to surface clearly, not to crash on.
- Free tier is RATE-LIMITED (429). That's exactly why we support multiple keys.

Use the `requests` library (add it) OR the `openai` SDK pointed at the GitHub
base_url. Prefer plain `requests` to avoid SDK/version coupling — fewer moving
parts on Python 3.12. Implement a real HTTP timeout.

====================================================================
KEY MANAGEMENT — comma-separated keys with failover
====================================================================
The user will supply TWO PATs from two GitHub accounts, comma-separated, so if
one is rate-limited the other is used. Read keys from, in priority order:
  1. environment variable GITHUB_MODELS_KEYS  (comma-separated)
  2. a local file  .env  at project root with a line
     GITHUB_MODELS_KEYS=key1,key2
  3. config.GITHUB_MODELS_KEYS (default "")  -- but NEVER hardcode real keys.
Parse into a list, strip whitespace, drop empties.

Failover behaviour in the VLM client:
- Try key[0]. On HTTP 429 (rate limit) or 401/403 (bad/expired key), rotate to
  the next key and retry the SAME request. On network error/timeout, try the
  next key too.
- Remember the last-good key index and start there next time (simple round-robin
  starting point) so you don't keep hitting an exhausted key first.
- If ALL keys fail: return a structured "unavailable" result (NOT an exception)
  so the pipeline degrades to YOLO-only. Log the reason (rate-limited / auth /
  network) once per event, not per retry.
- NEVER print full keys in logs — mask to last 4 chars.

SECURITY: add `.env` to .gitignore (it may already be ignored via data/ rules —
make sure `.env` specifically is ignored). Provide a `.env.example` with
  GITHUB_MODELS_KEYS=your_first_pat,your_second_pat
and a README note on how to create fine-grained PATs with "Models" access.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing:
- config.py                  (flags incl. ENABLE_VLM, ENABLE_OCR; add VLM section)
- accessai/visitor_event.py  (fields scene_summary, ocr_text ALREADY EXIST)
- accessai/pipeline.py       (Phase-2 sets identity; Phase-5 sets is_spoof;
                              Phase-3 sets objects; Pipeline.__init__ accepts
                              vlm=, vlm_enabled=, ocr=, ocr_enabled=)
- accessai/context_engine.py (infer_intent ALREADY reads ev.ocr_text for the
                              courier_hit branch -> "likely delivery" 0.85;
                              add a COURIER_KEYWORDS source)
- accessai/accessibility.py  (compose_announcement ALREADY appends "Label reads:
                              <ocr>" and the scene_summary for unknowns — inert
                              until now)
- run.py                     (module instantiation + injection)

The scene_summary + ocr_text plumbing is ALREADY wired and inert. Phase 6 builds
the VLM client, fills those two fields for unknowns, and adds courier keywords.
Restate understanding in 3-4 bullets before coding.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Add pinned:  requests==2.32.3   python-dotenv==1.0.1
(python-dotenv to load .env; or parse .env manually if you prefer no dep — but
dotenv is clean and tiny.)

--- 2) config.py — add a VLM / OCR section ---
Keep ENABLE_VLM, ENABLE_OCR; set BOTH True at end of phase. Add:
  VLM_BASE_URL = "https://models.github.ai/inference"
  VLM_MODEL = "gpt-4o-mini"
  VLM_TIMEOUT = 20                 # seconds per HTTP attempt
  VLM_MAX_TOKENS = 300
  VLM_TEMPERATURE = 0.2
  GITHUB_MODELS_KEYS = ""          # leave empty; real keys come from env/.env
  VLM_ONLY_FOR_UNKNOWN = True      # skip VLM when a known face is recognised
  VLM_JPEG_QUALITY = 80            # downscale/encode for smaller/faster uploads
  VLM_MAX_IMAGE_WIDTH = 768        # resize before sending to save tokens/time
  # Courier keywords used by the context engine's "likely delivery" upgrade:
  COURIER_KEYWORDS = ["bluedart","blue dart","dtdc","delhivery","ekart","xpressbees",
                      "amazon","flipkart","fedex","dhl","india post","speed post",
                      "professional couriers","gati","ecom express","shadowfax",
                      "swiggy","zomato","dunzo"]
Add a comment: keys are read from env GITHUB_MODELS_KEYS or .env, never hardcoded.

--- 3) accessai/vlm_module.py  (NEW) ---
Mirror the module pattern (guarded imports, available(), logging). Class:

class VLMModule:
  __init__(self, base_url, model, keys_csv="", timeout=20, max_tokens=300,
           temperature=0.2, jpeg_quality=80, max_width=768):
     - Load keys: prefer env GITHUB_MODELS_KEYS, else parse keys_csv (which run.py
       fills from .env/config). Store self.keys (masked in logs), self._idx=0.
     - self._ready = len(self.keys) > 0. Log "N key(s) loaded" (masked) or a
       clear "no keys -> VLM disabled, will use YOLO-only".
  available(self) -> bool: self._ready and requests imported.
  _encode(self, frame_bgr) -> str: resize to max_width (keep aspect), JPEG-encode
     at jpeg_quality, base64 -> "data:image/jpeg;base64,...".
  _chat(self, system, user_text, frame_bgr) -> dict:
     Build the OpenAI-style body; loop over keys starting at self._idx:
       - POST with Authorization: Bearer key, timeout=self.timeout.
       - 200 -> parse choices[0].message.content; set self._idx to this key;
         return {"ok":True,"text":content}.
       - 429/401/403 -> log masked reason, rotate to next key, continue.
       - network/timeout -> log, rotate, continue.
     If all keys exhausted -> return {"ok":False,"reason":"..."}.
  describe_scene(self, frame_bgr) -> str:
     system = "You describe a person at a front door for a BLIND user. Be brief,
       factual, and CONSERVATIVE. One or two short sentences. Never guess identity
       or intent as certain. Do not say 'definitely'."
     user = "Describe the visitor: appearance, clothing, and anything they are
       carrying. If they wear a delivery/company uniform, mention it cautiously."
     Return text on ok else "".
  read_labels(self, frame_bgr) -> str:
     system = "You read visible text from labels, parcels, or uniforms in the
       image. Output ONLY the text you can actually read, comma-separated. If no
       readable text, output an empty string."
     user = "Read any courier name, parcel label, or ID text visible."
     Return text on ok else "".
  (Optionally combine both into ONE call returning JSON {scene, labels} to save
   quota — if you do, parse defensively and fall back to "" on parse failure.
   Saving an API call matters on a rate-limited free tier, so ONE combined call
   is PREFERRED. Document the choice.)

--- 4) accessai/ocr_module.py  (NEW, thin) ---
Per the user's decision, OCR REUSES the VLM (no separate OCR engine now). Make a
tiny OCRModule that wraps a VLMModule reference:
  class OCRModule:
    __init__(self, vlm): self.vlm = vlm
    available(self): return self.vlm is not None and self.vlm.available()
    read(self, frame_bgr) -> str: return self.vlm.read_labels(frame_bgr)
This keeps the pipeline's ocr.* interface stable so a local PaddleOCR backend can
replace it later with zero pipeline change. (If you used the COMBINED single-call
approach in VLMModule, OCRModule.read can return the cached labels from the last
describe call for the same frame to avoid a second API hit — implement a tiny
per-frame cache keyed by id(frame) or a hash, else just call read_labels.)

--- 5) accessai/pipeline.py — call the VLM for UNKNOWNS only ---
AFTER identity (P2), anti-spoof (P5), and object detection (P3) are done, and
BEFORE infer_intent, insert:

  # --- VLM scene description + OCR (Phase 6), UNKNOWN visitors only ---
  is_unknown = (not ev.identity.known) and (ev.visitor_count > 0 or ev.detected_objects)
  if (self.vlm_enabled and self.vlm is not None and self.vlm.available()
          and is_unknown and (not config.VLM_ONLY_FOR_UNKNOWN or not ev.identity.known)):
      combined = None
      try:
          # PREFERRED: one combined call returns scene + labels
          scene, labels = self.vlm.describe_and_read(frame_bgr)  # if implemented
      except AttributeError:
          scene = self.vlm.describe_scene(frame_bgr)
          labels = ""
      ev.scene_summary = scene or ""
      # OCR (reuses VLM)
      if self.ocr_enabled and self.ocr is not None and self.ocr.available():
          ev.ocr_text = (labels or self.ocr.read(frame_bgr) or "")
      elif labels:
          ev.ocr_text = labels

  # (infer_intent already upgrades to "likely delivery" 0.85 when a courier
  #  keyword appears in ev.ocr_text; accessibility already appends scene_summary
  #  and "Label reads: <ocr>" — no change needed there.)

IMPORTANT: pass config into pipeline (it may already import config; if not, import
accessai config values via the constructor or module import consistent with the
existing code). Do NOT call the VLM for known faces. Do NOT block the request for
longer than the VLM timeout. Snapshot + db.save_event + return unchanged.

Also: make sure context_engine.infer_intent uses config.COURIER_KEYWORDS (pass
them in or import) rather than a hardcoded list, so the courier upgrade actually
fires. Keep the function pure — accept keywords as an argument with a default, and
have the pipeline/caller pass config.COURIER_KEYWORDS.

--- 6) run.py — instantiate + inject VLM and OCR ---
Load keys from .env/env (python-dotenv load_dotenv() at startup). Build:
  vlm = None
  if config.ENABLE_VLM:
      vlm = VLMModule(base_url=config.VLM_BASE_URL, model=config.VLM_MODEL,
                      keys_csv=os.getenv("GITHUB_MODELS_KEYS", config.GITHUB_MODELS_KEYS),
                      timeout=config.VLM_TIMEOUT, max_tokens=config.VLM_MAX_TOKENS,
                      temperature=config.VLM_TEMPERATURE,
                      jpeg_quality=config.VLM_JPEG_QUALITY,
                      max_width=config.VLM_MAX_IMAGE_WIDTH)
  ocr = OCRModule(vlm) if config.ENABLE_OCR else None
Pass into Pipeline (keep prior args): vlm=, vlm_enabled=, ocr=, ocr_enabled=.
Log masked key count + chosen model. App MUST start with zero keys (VLM disabled,
YOLO-only).

--- 7) web UI — surface scene description + label text ---
- Current Visitor card: show ev.scene_summary (a "Scene" line) and ev.ocr_text (a
  "Label reads" line) when present. If intent == "likely delivery" and ocr has a
  courier keyword, show a small "📦 Delivery" chip.
- History items: show a truncated scene summary if present.
- Add a tiny status indicator somewhere: "VLM: on (gpt-4o-mini, 2 keys)" vs
  "VLM: off (YOLO-only)" from a new GET /vlm_status route (returns masked key
  count, model, available bool). Vanilla JS, no CDN.

--- 8) Flip flags ---
Set ENABLE_VLM = True and ENABLE_OCR = True in config.py.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Install: pip install -r requirements.txt.
2. Keys: create a local .env with GITHUB_MODELS_KEYS=key1,key2 (the user will put
   REAL keys; for your test you may use placeholders and EXPECT auth failover to
   trigger the graceful path). Confirm keys are read + masked in logs.
3. Syntax: python -m py_compile on every .py; fix all errors.
4. Start: python3 run.py — confirm VLM logs masked key count + model, and
   GET /vlm_status works. App MUST start with no keys (YOLO-only).
5. Unknown-visitor path WITH working keys (if the user provides real keys, or you
   can reach the API): Ring with an unknown person / a parcel image -> event has
   non-empty scene_summary; if a courier label is visible, ocr_text has the name
   and intent becomes "likely delivery" (0.85) with announcement "... Likely a
   delivery. Label reads: <name>." Paste the event JSON.
6. Known-visitor path: Ring with a known face -> confirm the VLM is SKIPPED
   (scene_summary + ocr_text empty; no API call made). This is the latency
   optimization — verify it explicitly (log that VLM was skipped for known).
7. Failover: with two keys where the FIRST is invalid/exhausted, confirm the
   client rotates to the second and still succeeds (or, with both invalid,
   returns unavailable and the event falls back to YOLO-only WITHOUT crashing).
   Report what you observed (you can simulate 429/401 by using a bad first key).
8. Non-regression: Phases 1–5 all behave (face naming, YOLO, intent, TTS, /reply,
   /mode, anti-spoof downgrade). Conservative language preserved. If you cannot
   reach the API in the sandbox, prove the wiring deterministically (stub _chat to
   return a canned scene+labels) and SAY so, as in prior phases.

====================================================================
GUARDRAILS
====================================================================
- KNOWN faces never trigger a VLM call (cost + latency + privacy).
- All keys failing => structured unavailable => YOLO-only fallback, never a crash.
- Never log full API keys (mask to last 4). Never commit .env; add it to .gitignore.
- One combined VLM call (scene+labels) is preferred to conserve the free tier.
- Real HTTP timeout on every attempt; the request thread must not hang.
- context_engine stays pure; pass COURIER_KEYWORDS in, don't hardcode.
- Do not open a camera outside accessai/camera.py. Do not rename VisitorEvent
  fields or Database methods. Match existing style.

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## Before you paste this, do ONE thing:
Create the two GitHub PATs (fine-grained tokens with **Models** access) from two
GitHub accounts at github.com/settings/personal-access-tokens, then make a `.env`
file at the project root:

```
GITHUB_MODELS_KEYS=github_pat_FIRST,github_pat_SECOND
```

The agent's prompt tells it to read keys from `.env` and never hardcode them.

## After Phase 6, send me a report with:
1. Masked key-count + model in the startup log; `/vlm_status` output.
2. Unknown-visitor event JSON with non-empty `scene_summary` and (if a label was
   visible) `ocr_text` + "likely delivery" upgrade.
3. Explicit confirmation the VLM was **skipped for a known face** (the latency win).
4. Failover result (first key bad → second key used, or both bad → YOLO-only).
5. Whether you tested against the real API or stubbed it (method honesty).
6. Any errors + fixes; confirmation Phases 1–5 didn't regress.

Then I'll give you the **Phase 7 prompt** (Speech Recognition — Whisper + VAD),
which transcribes what the visitor says and adds it to the announcement.
