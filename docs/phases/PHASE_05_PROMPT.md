# PHASE 5 PROMPT — Face Anti-Spoofing / Liveness

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–4 complete).

---

```
You are continuing the AccessAI project. Phases 1 (Foundation), 2 (Face
Recognition), 3 (Object Detection + Context/Intent), and 4 (Accessibility Output
— TTS, Blind/Deaf, two-way reply) are COMPLETE and verified. Build ONLY Phase 5
now: FACE ANTI-SPOOFING / LIVENESS. Do not build later phases.

====================================================================
WHY THIS PHASE MATTERS (the security gate)
====================================================================
Without liveness, someone holding a printed photo or a phone screen showing
"Rahul" makes the system announce "Rahul is at the door." That is a security
failure for an accessibility product a blind user trusts. Phase 5 inserts a
liveness check so a flat photo/screen is treated as NOT a real present person,
and a matched-but-spoofed face is DOWNGRADED to Unknown before it reaches the
announcement.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing anything:
- config.py                  (flags incl. ENABLE_ANTISPOOF; add an Anti-spoof section)
- accessai/visitor_event.py  (fields spoof_score:float=1.0, is_spoof:bool=False
                              ALREADY EXIST; face_box exists)
- accessai/face_module.py    (identify() returns list of {name,confidence,box,
                              det_score}; the largest face is chosen in pipeline)
- accessai/pipeline.py       (Phase-2 face block sets ev.identity + ev.face_box;
                              Pipeline.__init__ already accepts antispoof=,
                              antispoof_enabled=)
- accessai/context_engine.py (infer_intent already has an is_spoof branch at top:
                              returns "possible spoof attempt", 0.6)
- accessai/accessibility.py  (compose_announcement already has a spoof branch:
                              "Warning. A face was shown ... appears to be a photo.")
- run.py                     (module instantiation + injection)

The spoof plumbing is ALREADY wired end-to-end and inert. Phase 5's job is to
build the actual detector, compute ev.spoof_score / ev.is_spoof in the pipeline,
and make the identity DOWNGRADE happen. Restate understanding in 3-4 bullets
before coding.

====================================================================
MODEL CHOICE — Silent-Face-Anti-Spoofing (CPU, ONNX/PyTorch)
====================================================================
Use the MiniFASNet-based "Silent-Face-Anti-Spoofing" approach (originally by
MiniVision). It is lightweight and CPU-friendly. It classifies a face crop as
real vs. spoof (photo/screen/mask).

IMPLEMENTATION REALITY — read carefully and choose the most robust available
option, in THIS priority order, and REPORT which one you used:

  OPTION A (preferred if installable): a pip package that wraps Silent-Face,
    e.g. try `pip install silent-face-anti-spoofing` or an equivalently
    maintained package. If it installs cleanly on Python 3.12 / CPU and exposes a
    predict on a face crop, use it.

  OPTION B (robust fallback, self-contained): vendor the two small MiniFASNet
    ONNX models into the repo under models/antispoof/ and run them with
    onnxruntime (already a dependency from Phase 2). The Silent-Face repo ships
    two model files (a 2.7_80x80 MiniFASNetV2 and a 4_0_0_80x80 MiniFASNetV1SE).
    If you can fetch these .onnx/.pth files, place them under models/antispoof/
    and load with onnxruntime. Preprocess: crop the face box with the model's
    expected scale/padding, resize to 80x80, normalize, run both models, sum the
    softmax outputs, take argmax; class index 1 = real, {0,2} = spoof (photo/
    replay). Return the "real" probability as the score.

  OPTION C (last-resort heuristic, ONLY if A and B are both unavailable in this
    environment — and you MUST clearly flag it as a placeholder): a simple
    laplacian-variance + color/texture heuristic on the face crop that returns a
    liveness score in [0,1]. This is NOT production-grade; it exists so the
    pipeline is functional and testable now, and MUST be logged as
    "[AntiSpoofModule] WARNING: using heuristic placeholder, replace with
    MiniFASNet models for real security." Design the class so swapping in the
    real model later requires NO pipeline change.

Whichever option: the module's PUBLIC interface is identical (below), so the rest
of the system doesn't care which backend ran.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
- onnxruntime is already present (Phase 2). If you use a pip wrapper (Option A),
  add it pinned. If Option B/C, no new hard dep beyond onnxruntime/opencv/numpy.
- Add a comment documenting which option you chose and, for Option B, where the
  model files must live (models/antispoof/*.onnx) and that they are ~2 MB total.

--- 2) config.py — add an Anti-spoofing section ---
Keep ENABLE_ANTISPOOF; set it True at the end of this phase. Add:
  ANTISPOOF_MODEL_DIR = os.path.join(BASE_DIR, "models", "antispoof")
  ANTISPOOF_MIN_SCORE = 0.55   # >= this "real" score => live person; else spoof
  ANTISPOOF_BACKEND = "auto"   # "auto" picks A->B->C; or force "onnx"/"heuristic"
Add a comment explaining the threshold meaning and that raising it is stricter
(fewer spoofs accepted, but more real faces might be rejected in poor light).

--- 3) accessai/antispoof.py  (NEW) ---
Mirror the module pattern (guarded imports, available(), logging). Class:

class AntiSpoofModule:
  __init__(self, model_dir, min_score=0.55, backend="auto"):
     - Try to initialise the chosen backend (A/B/C per the priority + the
       backend override). Set self._backend_name accordingly
       ("silent-face-pip" | "onnx-minifasnet" | "heuristic" | "none").
     - Wrap in try/except; on total failure self._ready=False and log; never raise.
  available(self) -> bool
  backend_name(self) -> str
  score(self, frame_bgr, box) -> float:
     - box is (x1,y1,x2,y2) of the face (the pipeline passes ev.face_box).
     - If not available() or box invalid/zero-area: return 1.0 (fail-OPEN so a
       broken detector never blocks a real known visitor — but log a warning
       once). Document this choice: we prefer not to lock out real users if the
       liveness model is missing; the security benefit applies only when the
       model is actually loaded.
     - Crop the face region (with a little padding, clamped to frame bounds),
       run the backend, return the "real" probability in [0,1].
  is_live(self, score) -> bool:  return score >= self.min_score.

Keep all preprocessing details INSIDE this module.

--- 4) accessai/pipeline.py — compute spoof + DOWNGRADE identity ---
Inside run_once, AFTER the Phase-2 face block has set ev.identity and ev.face_box,
and BEFORE object detection / infer_intent, insert:

  # --- Liveness / anti-spoofing (Phase 5) ---
  if (self.antispoof_enabled and self.antispoof is not None
          and self.antispoof.available() and ev.face_box != (0,0,0,0)):
      ev.spoof_score = float(self.antispoof.score(frame_bgr, ev.face_box))
      ev.is_spoof = not self.antispoof.is_live(ev.spoof_score)
      if ev.is_spoof:
          # A flat photo/screen must not be announced as a known person.
          ev.identity = Identity(known=False, name="Unknown",
                                  confidence=ev.identity.confidence)
  # (context_engine.infer_intent already prioritises ev.is_spoof; accessibility
  #  .compose_announcement already has the spoof warning sentence — no change
  #  needed there.)

Ensure Identity is imported (it is, from Phase 2). Do NOT touch the object step,
infer_intent call, or access.deliver call — they already react to is_spoof.
Snapshot + db.save_event + return unchanged.

--- 5) run.py — instantiate + inject AntiSpoofModule ---
Import AntiSpoofModule. Build:
  antispoof = None
  if config.ENABLE_ANTISPOOF:
      antispoof = AntiSpoofModule(model_dir=config.ANTISPOOF_MODEL_DIR,
                                  min_score=config.ANTISPOOF_MIN_SCORE,
                                  backend=config.ANTISPOOF_BACKEND)
Pass into Pipeline (keep prior args):
  pipeline = Pipeline(..., antispoof=antispoof,
                      antispoof_enabled=config.ENABLE_ANTISPOOF)
Log the chosen backend on startup (e.g. "[AccessAI] Liveness backend: ...").

--- 6) web UI — surface liveness ---
- Current Visitor card: if ev.is_spoof, show a red "⚠ SPOOF SUSPECTED" badge and
  the spoof warning announcement. Otherwise optionally show a small "live ✓
  (score 0.xx)" indicator when a known/unknown real face was checked.
- History items: mark spoof events distinctly (red).
- Vanilla JS, no CDN.

--- 7) Flip the flag ---
Set ENABLE_ANTISPOOF = True in config.py.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Install any new dep; report which backend option (A/B/C) actually loaded and
   why (e.g. "pip package unavailable on 3.12, used ONNX MiniFASNet" or "models
   could not be fetched in sandbox, used heuristic placeholder — flagged").
2. Syntax: python -m py_compile on every .py; fix all errors.
3. Start: python3 run.py — confirm the anti-spoof backend logs its name and the
   app starts. App MUST start if the model is missing (fail-open, logged).
4. Spoof path: present a FLAT photo/screen of a known (or any) face to the camera
   -> expect ev.is_spoof=true, ev.identity downgraded to Unknown, intent
   "possible spoof attempt", announcement "Warning. A face was shown ... appears
   to be a photo.", card shows red badge. Paste the event JSON.
5. Live path: a real face -> ev.is_spoof=false, ev.spoof_score >= threshold,
   normal identity + announcement. Paste the event JSON.
   (If you cannot present a live face/photo in the sandbox, be HONEST like prior
    phases: prove the DOWNGRADE logic deterministically by feeding a known-
    identity event through the pipeline with a stubbed antispoof.score() that
    returns a low value, and show identity flips to Unknown + intent becomes
    spoof. Also show a high-score stub keeps identity. State exactly what you did.)
6. Fail-open check: with the model dir empty / backend "none", score() returns
   1.0, is_spoof=false, and a real known visitor is still announced normally
   (a broken liveness model must not lock out real users). Confirm + report.
7. Non-regression: Phases 1–4 all behave (face naming, YOLO, intent, TTS speaks,
   /reply, /mode, /history, /snapshot, big-text/flash Deaf mode). Conservative
   language preserved.

====================================================================
GUARDRAILS
====================================================================
- FAIL-OPEN when the detector is unavailable (return score 1.0), FAIL-CLOSED on a
  confident spoof (downgrade identity). Document both explicitly in code.
- The spoof check runs only when there IS a face_box; never crash on empty boxes.
- Do not open a camera outside accessai/camera.py.
- Do not rename/remove VisitorEvent fields or Database methods.
- Do not alter the already-correct is_spoof branches in context_engine or
  accessibility — just feed them real values.
- If you must use the Option C heuristic, LABEL it loudly as a placeholder in
  logs + code + your report, and keep the interface identical so the real model
  drops in later with zero pipeline change.
- CPU-only. Match existing style (guarded imports, available(), WHY-docstrings).

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## After Phase 5, send me a report with:
1. Which backend option loaded (A pip / B ONNX MiniFASNet / C heuristic) and
   WHY — this is the most important line. If it's the heuristic placeholder, say
   so clearly so we plan to drop in real models before any real deployment.
2. Spoof-path event JSON (identity downgraded to Unknown, is_spoof=true).
3. Live-path event JSON (is_spoof=false, score ≥ threshold).
4. Fail-open confirmation (missing model → real visitor still announced).
5. Method honesty note (live photo vs. stubbed score) as in prior phases.
6. Any errors + fixes; confirmation Phases 1–4 didn't regress.

Then I'll give you the **Phase 6 prompt** (VLM Scene Description + OCR on labels)
— richer descriptions for unknown visitors and reading courier/parcel labels.
