# PHASE 9 PROMPT — Visitor Re-Identification + Auto-Enrollment

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1–8 complete).

---

```
You are continuing the AccessAI project. Phases 1–8 are COMPLETE and verified.
Build ONLY Phase 9 now: the MEMORY layer — VISITOR RE-IDENTIFICATION (recognise a
repeat UNKNOWN visitor by body/appearance) and AUTO-ENROLLMENT (cluster
repeatedly-seen unknown FACES and suggest saving them). Do not build later phases.

====================================================================
CRITICAL PRE-FLIGHT — PROTECT THE TORCH VERSION (read first, this is the risk phase)
====================================================================
The ML stack is on a PINNED, WORKING trio:
  torch==2.4.1  torchvision==0.19.1  torchaudio==2.4.1
The canonical Re-ID library `torchreid` PULLS torch and often forces a different
version — which in Phase 7 silently broke YOLO (predict() returned 0 detections
with NO error). DO NOT let that happen.

Rules for ANY pip install in this phase:
- BEFORE installing anything, record:
    python -c "import torch,torchvision; print(torch.__version__, torchvision.__version__)"
- PREFER a Re-ID approach that does NOT move torch (Options A/C below).
- If a package tries to change torch/torchvision/torchaudio: pin them in the SAME
  install command, or abandon that approach.
- AFTER any install, MANDATORY re-verify:
    1. torch is STILL 2.4.1 (reinstall the trio if it moved).
    2. YOLO still detects on bundled bus.jpg (bus + multiple persons, NOT zero).
- Report before/after torch + the YOLO check. This is non-negotiable.

scikit-learn (for DBSCAN) is torch-safe but pin it (scikit-learn==1.5.2) and still
run the post-install torch/YOLO check.

====================================================================
GOAL
====================================================================
Two related "memory" features, both operating on UNKNOWN visitors only:

(1) VISITOR RE-ID: for each unknown visitor, compute an appearance embedding from
    their body crop, store it in a gallery, and match new unknowns against recent
    ones. If the same person recurs, the event reports reid_seen_count so the
    announcement can say "The same unknown visitor has come 3 times today."

(2) AUTO-ENROLLMENT: accumulate unknown FACE embeddings over time; cluster them
    (DBSCAN). When a cluster reaches N sightings, surface a "Save this visitor?"
    suggestion in the UI so the user can promote them to a known face without
    manual photo registration.

Everything degrades gracefully: no Re-ID model / no sklearn => features are
skipped, the event proceeds exactly as Phase 8.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing:
- config.py                  (ENABLE_REID, ENABLE_AUTOENROLL flags exist; add
                              Re-ID + Auto-enroll sections)
- accessai/visitor_event.py  (fields reid_id:str|None, reid_seen_count:int ALREADY
                              EXIST)
- accessai/database.py       (tables reid_gallery AND unknown_face_clusters ALREADY
                              EXIST — with embedding LargeBinary columns; add
                              helper methods, don't rename tables)
- accessai/face_module.py    (identify() returns faces; for auto-enroll you need
                              the unknown face's EMBEDDING — see note below)
- accessai/pipeline.py       (Phase-2 identity, Phase-5 spoof, Phase-3 objects,
                              Phase-6 VLM, Phase-7 speech, Phase-8 translate;
                              Pipeline.__init__ accepts reid=, reid_enabled=,
                              autoenroll=, autoenroll_enabled=)
- accessai/context_engine.py (infer_intent + compose_announcement — accessibility
                              ALREADY has a "The same unknown visitor has come <N>
                              times today." branch keyed on reid_seen_count>=2,
                              inert until now)
- run.py                     (module instantiation + injection)

The reid_seen_count -> announcement plumbing is ALREADY wired and inert. Phase 9
builds the Re-ID + auto-enroll modules and fills reid_id/reid_seen_count + the
cluster suggestions. Restate understanding in 3-4 bullets before coding.

IMPORTANT interface note: auto-enrollment needs the UNKNOWN FACE EMBEDDING. The
Phase-2 FaceModule.identify() may not currently return the raw embedding. Add an
OPTIONAL method FaceModule.embed_largest_face(frame_bgr) -> (embedding|None, box)
that returns the normed embedding of the largest face, WITHOUT breaking identify().
Do not change identify()'s existing return shape.

====================================================================
RE-ID MODEL CHOICE — torch-safe priority (REPORT which you used)
====================================================================
  OPTION A (preferred, torch-safe): OSNet exported to ONNX, run via onnxruntime
    (already a dependency). If you can obtain an osnet_x0_25 or osnet_x1_0 .onnx
    (place under models/reid/), load with onnxruntime. Preprocess a body crop:
    resize to 256x128, RGB, normalise (ImageNet mean/std), CHW, run, L2-normalise
    the output feature vector. This adds NO torch movement.

  OPTION B (torchreid): only if A is impossible AND you can install it WITHOUT
    moving torch (pin torch in the same command; re-verify YOLO after). HIGH RISK
    — prefer A. If you use B, prove torch stayed 2.4.1.

  OPTION C (fallback placeholder, torch-safe, ALWAYS works now): an appearance
    embedding from the body crop using color/texture — e.g. an HSV color histogram
    (e.g. 8x8x8 bins) concatenated with a coarse spatial layout, L2-normalised.
    This is NOT as robust as OSNet but is a functional, dependency-free stand-in so
    Re-ID works today. LABEL it loudly as a placeholder in logs + code + report,
    and keep the interface IDENTICAL so an ONNX OSNet drops in later with zero
    pipeline change. (Same pattern you used for the anti-spoof heuristic in P5.)

Default to A if a model is available; otherwise C. Make the backend configurable.

The "body crop" for Re-ID: use the largest YOLO "person" detection box from
ev.detected_objects (Phase 3 already produced these). If no person box, fall back
to the whole frame or the face box expanded downward. Document the choice.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Add pinned:  scikit-learn==1.5.2   (DBSCAN for auto-enroll)
For Re-ID Option A/C: no new heavy dep (onnxruntime + opencv + numpy already
present). If you attempt Option B, document the exact pinned install you used and
the torch re-verify result. Add a comment noting the torch-safety requirement.

--- 2) config.py — add Re-ID + Auto-enroll sections ---
Keep ENABLE_REID, ENABLE_AUTOENROLL; set BOTH True at end of phase. Add:
  # Re-ID
  REID_BACKEND = "auto"            # auto -> onnx if model present else histogram
  REID_MODEL_DIR = os.path.join(BASE_DIR, "models", "reid")
  REID_MATCH_THRESHOLD = 0.75      # cosine sim to call it the same person
  REID_GALLERY_TTL_HOURS = 24      # only match against sightings within this window
  REID_MAX_GALLERY = 500           # cap stored embeddings (evict oldest)
  # Auto-enroll
  AUTOENROLL_EPS = 0.35            # DBSCAN eps on (1 - cosine) distance for faces
  AUTOENROLL_MIN_SAMPLES = 3       # DBSCAN min_samples
  AUTOENROLL_SUGGEST_AFTER = 5     # cluster size that triggers a "save?" suggestion
Add comments explaining thresholds and the 24h "today" window for the "N times
today" announcement.

--- 3) accessai/reid_module.py  (NEW) ---
Mirror the module pattern (guarded imports, available(), logging).

class ReidModule:
  __init__(self, backend="auto", model_dir=..., match_threshold=0.75,
           ttl_hours=24, max_gallery=500, db=None):
     - Pick backend: onnx if a model file exists in model_dir, else histogram
       placeholder (log loudly if placeholder). Store db handle for gallery I/O.
  available(self) -> bool ; backend_name(self) -> str.
  embed(self, frame_bgr, person_box=None) -> np.ndarray | None:
     - Crop the body (person_box or fallback), preprocess per backend, return an
       L2-normalised float32 vector. None on failure.
  identify(self, embedding, now_iso) -> tuple[str, int]:
     - Compare against gallery embeddings within ttl (cosine sim). If best >=
       threshold: reuse that reid_id, increment its seen_count + last_seen, return
       (reid_id, new_count). Else: mint a new reid_id (e.g. "v_" + short uuid),
       insert with seen_count=1, return (reid_id, 1).
     - Evict entries older than ttl and cap to max_gallery (oldest first).
  process(self, frame_bgr, ev, now_iso) -> None:
     - Convenience: emb = embed(...); if emb is None return; (rid, count) =
       identify(emb, now_iso); ev.reid_id = rid; ev.reid_seen_count = count.
  Store/read embeddings via the EXISTING reid_gallery table (add Database methods
  reid_add / reid_recent / reid_touch / reid_evict — do NOT rename the table).
  Serialize embeddings as bytes (np.tobytes + dtype/shape or np.save to BytesIO).

--- 4) accessai/auto_enroll.py  (NEW) ---
Mirror the module pattern. Uses scikit-learn DBSCAN on UNKNOWN FACE embeddings.

class AutoEnrollModule:
  __init__(self, db, eps=0.35, min_samples=3, suggest_after=5):
     - guarded import of sklearn.cluster.DBSCAN; available() reflects it.
  add_unknown_face(self, embedding, event_id, now_iso) -> None:
     - store the embedding in unknown_face_clusters (cluster_id NULL/-1 initially).
  recompute(self) -> list[dict]:
     - load recent unknown-face embeddings; run DBSCAN with metric="cosine"
       (or precomputed 1-cosine distances), eps/min_samples from config;
       assign cluster ids; for any cluster whose size >= suggest_after and not yet
       marked suggested, return a suggestion {cluster_id, size, sample_event_ids,
       representative_embedding}. Mark suggested to avoid repeat prompts.
  suggestions(self) -> list[dict]:  currently-open "save this visitor?" prompts.
  confirm(self, cluster_id, name) -> bool:
     - promote a cluster to a known face: pick a representative embedding, add it
       to the FaceModule's in-memory gallery AND known_faces table under `name`
       so recognition works next time. (Take a FaceModule ref, or return the
       embedding for run.py/server to enroll — choose one clean approach.)
  dismiss(self, cluster_id) -> bool: mark suggestion dismissed.
  Add Database helpers on the existing unknown_face_clusters table (add/query/mark)
  — do NOT rename the table.

--- 5) accessai/face_module.py — add embed_largest_face (non-breaking) ---
Add:
  def embed_largest_face(self, frame_bgr) -> tuple[np.ndarray|None, tuple]:
     Run detection; if faces, return (largest_face.normed_embedding, bbox_ints);
     else (None, (0,0,0,0)). Do NOT change identify().

--- 6) accessai/pipeline.py — wire Re-ID + auto-enroll (UNKNOWN only) ---
AFTER Phase-8 translation and BEFORE infer_intent/access.deliver, insert:

  is_unknown_person = (not ev.identity.known) and ev.visitor_count > 0 and not ev.is_spoof
  if is_unknown_person:
      now_iso = ev.timestamp
      # Re-ID
      if self.reid_enabled and self.reid is not None and self.reid.available():
          person_box = self._largest_person_box(ev)   # from ev.detected_objects
          self.reid.process(frame_bgr, ev, now_iso)    # fills reid_id + count
      # Auto-enroll: stash the unknown face embedding for clustering
      if self.autoenroll_enabled and self.autoenroll is not None and self.autoenroll.available():
          if self.face is not None and self.face.available():
              emb, _box = self.face.embed_largest_face(frame_bgr)
              if emb is not None:
                  self.autoenroll.add_unknown_face(emb, ev.event_id, now_iso)

  # accessibility.compose_announcement already emits "The same unknown visitor has
  # come <N> times today." when reid_seen_count >= 2 — no change needed.

Add a helper self._largest_person_box(ev). Do NOT run Re-ID for known or spoofed
visitors. Snapshot + db.save_event + return unchanged.

Recompute clustering periodically, NOT on every trigger (DBSCAN over all history
is O(n^2)). Options: recompute every K unknown events, or on a timer thread, or
lazily when /suggestions is requested. Pick one, document it, keep it cheap.

--- 7) run.py — build + inject ReidModule and AutoEnrollModule ---
  reid = None
  if config.ENABLE_REID:
      reid = ReidModule(backend=config.REID_BACKEND, model_dir=config.REID_MODEL_DIR,
                        match_threshold=config.REID_MATCH_THRESHOLD,
                        ttl_hours=config.REID_GALLERY_TTL_HOURS,
                        max_gallery=config.REID_MAX_GALLERY, db=db)
  autoenroll = None
  if config.ENABLE_AUTOENROLL:
      autoenroll = AutoEnrollModule(db=db, eps=config.AUTOENROLL_EPS,
                        min_samples=config.AUTOENROLL_MIN_SAMPLES,
                        suggest_after=config.AUTOENROLL_SUGGEST_AFTER)
Pass into Pipeline (keep prior args): reid=, reid_enabled=, autoenroll=,
autoenroll_enabled=. Give autoenroll access to the FaceModule (for confirm()) —
pass `face` into it or handle confirm() in the server using pipeline.face. Log
backends + whether Re-ID is the placeholder. App MUST start if either is missing.

--- 8) server.py — suggestions + confirm/dismiss + status ---
- GET "/suggestions": pipeline.autoenroll.suggestions() (open "save this visitor?"
  prompts with size + a sample snapshot event id).
- POST "/suggestions/confirm" {"cluster_id":..., "name":...}: promote to known
  face (via autoenroll.confirm or pipeline.face enrollment). Return ok + new
  known_count. Broadcast so UI refreshes.
- POST "/suggestions/dismiss" {"cluster_id":...}: dismiss.
- GET "/reid_status": {enabled, backend, gallery_size, placeholder:bool}.
- Keep the event broadcast so the "N times today" + suggestions update live.

--- 9) web UI — repeat-visitor + suggestions ---
- Current Visitor card: if reid_seen_count >= 2, show a "🔁 Seen <N>× today" badge
  and the "same unknown visitor" announcement.
- A "Suggestions" panel: list open "Save this visitor?" prompts (thumbnail from a
  sample event snapshot + a name input + Save / Dismiss buttons) wired to the
  routes above.
- Status pills: "Re-ID: on (onnx|histogram, gallery N)" and auto-enroll state.
- Vanilla JS, no CDN.

--- 10) Flip flags ---
Set ENABLE_REID = True and ENABLE_AUTOENROLL = True in config.py.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. PRE-FLIGHT: record torch/torchvision BEFORE installs.
2. Install scikit-learn (+ Re-ID model if using Option A). POST-INSTALL MANDATORY:
   confirm torch STILL 2.4.1 and YOLO bus.jpg still detects (bus + persons, not
   zero). Report both.
3. Which Re-ID backend loaded (A onnx / B torchreid / C histogram placeholder) and
   why. If placeholder, flag it clearly (like the P5 anti-spoof heuristic).
4. Syntax: python -m py_compile on every .py; fix all errors.
5. Start: python3 run.py — confirm Re-ID + auto-enroll backends log and the app
   starts. MUST start if either is unavailable.
6. Re-ID repeat detection: feed the SAME unknown person image through /trigger (or
   run_once) 3 times -> reid_seen_count increments 1,2,3; on the 2nd+ the
   announcement says "The same unknown visitor has come <N> times today." Feed a
   DIFFERENT unknown -> new reid_id, count 1. Paste the event JSONs. (You may reuse
   archived person photos / bus.jpg crops; SAY which images you used.)
7. TTL/threshold sanity: two clearly different people don't collapse to one
   reid_id; the same person within the window matches. Report the cosine sims you
   observed and whether you tuned REID_MATCH_THRESHOLD.
8. Auto-enroll: add the same unknown FACE >= AUTOENROLL_SUGGEST_AFTER times ->
   GET /suggestions returns a "save this visitor?" prompt; POST confirm with a
   name -> that face is now recognised as known on the next trigger. Paste the
   suggestion JSON + the post-confirm known result.
9. Non-regression: Phases 1–8 all behave (face naming, YOLO REAL detections,
   intent, TTS, /reply, /mode, anti-spoof, VLM-for-unknown, speech, translation).
   Conservative language preserved. Re-ID/auto-enroll skipped for KNOWN + SPOOF.

====================================================================
GUARDRAILS
====================================================================
- TORCH SAFETY IS PARAMOUNT: no install may move torch off 2.4.1; verify YOLO
  after. Prefer torch-free Re-ID (Option A/C).
- Re-ID + auto-enroll run for UNKNOWN, non-spoof visitors ONLY.
- DBSCAN must NOT run on every trigger (O(n^2)); recompute cheaply/periodically.
- Reuse the EXISTING reid_gallery + unknown_face_clusters tables; add methods, do
  NOT rename. Do not rename VisitorEvent fields.
- Placeholder Re-ID (histogram) must be LOUDLY labelled and interface-compatible
  with a future ONNX OSNet drop-in.
- Never crash on empty gallery / no person box / no face. Graceful everywhere.
- Do not open a camera outside accessai/camera.py. context_engine stays pure.
- Match existing style (guarded imports, available(), WHY-docstrings).

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification (INCLUDING torch + YOLO check) and report real output, fixing errors
before finishing.
```

---

## After Phase 9, send me a report with:
1. **torch before/after + YOLO bus.jpg sanity check** (mandatory — scikit-learn
   and any Re-ID model install are the risk).
2. Which Re-ID backend loaded (A ONNX OSNet / B torchreid / C histogram
   placeholder) and why. If placeholder, note it for the deployment-readiness list.
3. Re-ID repeat-detection event JSONs (same person → count 1,2,3 + "N times today"
   announcement; different person → new id).
4. Threshold/TTL sanity (different people don't merge; cosine sims observed).
5. Auto-enroll suggestion JSON + post-confirm known-recognition result.
6. Method honesty (which images/stubs) + errors + fixes; Phases 1–8 non-regression.

Then I'll give you the **Phase 10 prompt** — the FINAL phase: Wake Word + Voice
Commands, plus end-to-end hardening and ESP32/Flutter readiness. That closes the
build.
