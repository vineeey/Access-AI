# PHASE 2 PROMPT — Face Recognition (InsightFace)

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (same `AccessAI` workspace that now has a working Phase 1).

---

```
You are continuing the AccessAI project. Phase 1 (Foundation) is COMPLETE and
verified: FastAPI + web dashboard, camera thread, SQLite, and a manual "Ring"
trigger that creates/stores/show a VisitorEvent with a snapshot. Build ONLY
Phase 2 now: FACE RECOGNITION. Do not build later phases.

====================================================================
STEP 0 — READ THE CURRENT CODE BEFORE CHANGING ANYTHING
====================================================================
Read these files fully and match their exact interfaces:
- config.py                     (feature flags incl. ENABLE_FACE; paths)
- accessai/visitor_event.py     (Identity + VisitorEvent; the spine)
- accessai/pipeline.py          (Pipeline.__init__ already accepts face=,
                                 face_enabled=; run_once has TODO markers)
- accessai/database.py          (has a known_faces table already; Database API)
- accessai/server.py            (make_app factory, LatestFrame, routes,
                                 broadcast, _jsonify)
- accessai/camera.py            (do NOT open a camera anywhere else)
- run.py                        (builds Database + Pipeline + camera thread)
- web/index.html, web/app.js, web/style.css

Do NOT restructure anything. Phase 2 only FILLS existing VisitorEvent fields
(identity, face_box, visitor_count), FLIPS one flag, injects one module, and adds
enrollment. Confirm your understanding of these interfaces in 3-4 bullets before
coding.

====================================================================
GOAL
====================================================================
On "Ring", detect faces in the current frame, and if a face matches a registered
person, set the event's identity to that person; otherwise "Unknown". Provide a
way to REGISTER (enroll) known people from the live camera and from image files.
Everything must run on CPU, Python 3.12, Linux.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Uncomment/add exactly these two (versions pinned, known-good on 3.12/CPU):
  insightface==0.7.3
  onnxruntime==1.18.1
Leave all other later-phase deps commented. Note in a comment that insightface
compiles a small C extension and needs build tools; if `pip install` fails with a
compiler error, the user should run: sudo apt install -y build-essential python3-dev

--- 2) config.py — add a Face recognition section ---
Add these keys (keep the existing ENABLE_FACE flag; set it to True at the end of
this phase):
  FACE_MODEL_NAME = "buffalo_l"        # InsightFace model pack (det + ArcFace)
  FACE_DET_SIZE = (640, 640)           # detector input size
  FACE_MATCH_THRESHOLD = 0.45          # cosine similarity; higher = stricter
  FACE_MIN_DET_SCORE = 0.5             # ignore very low-confidence detections
  FACE_CTX_ID = -1                     # -1 = CPU, 0 = first GPU
Add a comment: buffalo_l downloads ~300 MB to ~/.insightface/ on first run (one
time). Cosine similarity for normed embeddings is a dot product; same-person
pairs usually score > 0.5, different people < 0.3, so 0.45 is a safe default the
user can tune.

--- 3) accessai/face_module.py  (NEW) ---
Create a FaceModule class using InsightFace. Follow the SAME robustness pattern as
existing modules: a module-level try/except import guard, an available() method,
and print("[FaceModule] ...") logging.

Imports (guarded):
    from insightface.app import FaceAnalysis

Class FaceModule:
  __init__(self, known_dir, threshold=0.45, model_name="buffalo_l",
           det_size=(640,640), ctx_id=-1, min_det_score=0.5):
      - Store params. If insightface imported OK:
          print a one-time "loading (first run downloads ~300MB)" message,
          self.app = FaceAnalysis(name=model_name,
                                  allowed_modules=["detection","recognition"])
          self.app.prepare(ctx_id=ctx_id, det_size=det_size)
          self.known_embeddings = []   # list[np.ndarray]  (512-d, L2-normalised)
          self.known_names = []        # list[str] aligned with embeddings
          self.load_known()
      - Wrap the whole init body in try/except; on failure set self.app=None and
        log a helpful message (never raise — graceful degradation).

  available(self) -> bool:  return insightface imported AND self.app is not None.

  load_known(self) -> None:
      - Reset known_embeddings/names.
      - Walk known_dir recursively for *.jpg/*.jpeg/*.png. The person's NAME is
        the immediate parent folder name (data/known_faces/<Name>/x.jpg). If a
        file sits directly in known_dir, use its filename stem as the name.
      - For each image: cv2.imread -> self.app.get(img). If no face, log & skip.
        If multiple faces, take the LARGEST bbox. Append face.normed_embedding
        and the name.
      - Print a summary: how many embeddings for how many unique people.

  identify(self, frame_bgr) -> list[dict]:
      - If not available(): return [].
      - faces = self.app.get(frame_bgr).
      - For each face with det_score >= min_det_score:
          emb = face.normed_embedding
          best_name = "Unknown"; best_sim = 0.0
          if known_embeddings: compute cosine sim (np.dot) vs each; take the max;
            if max >= threshold -> best_name = that person's name; best_sim = max.
          Append {"name": best_name, "confidence": round(best_sim,3),
                  "box": (x1,y1,x2,y2) as ints from face.bbox,
                  "det_score": float(face.det_score)}.
      - Return the list (may be empty).

  enroll_from_image(self, name, image_bgr) -> tuple[bool, str]:
      - Detect faces; require EXACTLY ONE clear face (largest if >1, but warn).
        If none, return (False, "No face detected").
      - Save the image to known_dir/<name>/<timestamp>.jpg (make dirs).
        Use a passed-in or generated timestamp string; do NOT call datetime in a
        way that breaks — a simple time-based filename is fine.
      - Append the new embedding + name to the in-memory lists (so recognition
        works immediately WITHOUT a restart).
      - Return (True, "Enrolled <name>").

Add a small module-level cosine helper if you prefer, but np.dot on normed
embeddings is sufficient.

--- 4) accessai/pipeline.py — wire face recognition into run_once ---
At the top, also import Identity from .visitor_event.
Inside run_once, REPLACE the Phase-1 placeholder block (the part that sets
intent="unknown visitor" and announcement_text="Someone is at the door.") with:

  if self.face_enabled and self.face is not None and self.face.available():
      results = self.face.identify(frame_bgr)
      ev.visitor_count = len(results)
      if results:
          best = max(results, key=lambda r: (r["box"][2]-r["box"][0]) *
                                            (r["box"][3]-r["box"][1]))
          ev.face_box = tuple(best["box"])
          if best["name"] != "Unknown":
              ev.identity = Identity(known=True, name=best["name"],
                                     confidence=float(best["confidence"]))
          else:
              ev.identity = Identity(known=False, name="Unknown",
                                     confidence=float(best["confidence"]))
  # Interim announcement (Phase 4 will move sentence-composition into a proper
  # accessibility engine; keep it minimal + conservative here):
  if ev.identity.known:
      ev.intent = "known visitor"
      ev.announcement_text = f"{ev.identity.name} is at the door."
  elif ev.visitor_count > 0:
      ev.intent = "unknown visitor"
      ev.announcement_text = "An unknown visitor is at the door."
  else:
      ev.intent = "no visitor detected"
      ev.announcement_text = "The doorbell rang but no one is clearly visible."

Keep the existing snapshot + db.save_event + return logic unchanged. Leave all
other TODO markers (Phase 3/5/6/7/8/9) exactly as they are.

--- 5) run.py — instantiate and inject FaceModule ---
Import FaceModule. Before building Pipeline, create:
  face = None
  if config.ENABLE_FACE:
      face = FaceModule(known_dir=config.KNOWN_FACES_DIR,
                        threshold=config.FACE_MATCH_THRESHOLD,
                        model_name=config.FACE_MODEL_NAME,
                        det_size=config.FACE_DET_SIZE,
                        ctx_id=config.FACE_CTX_ID,
                        min_det_score=config.FACE_MIN_DET_SCORE)
Pass into the pipeline:
  pipeline = Pipeline(db=db, history_dir=config.HISTORY_DIR,
                      face=face, face_enabled=config.ENABLE_FACE)
Do not change the camera thread or server wiring otherwise.

--- 6) Enrollment: CLI + HTTP endpoint + UI ---
(a) enroll.py (NEW, project root) — a command-line enroller:
    Usage:
      python3 enroll.py "Rahul" path/to/1.jpg path/to/2.jpg ...   (from files)
      python3 enroll.py "Rahul" --camera                          (grab 1 frame)
    It builds a FaceModule (ENABLE_FACE not required), calls enroll_from_image for
    each source, and prints results. For --camera, open accessai.camera.Camera on
    config.CAMERA_SOURCE, read one good frame, enroll it. Handle "no face" cleanly.

(b) server.py — add two routes (do NOT break existing ones):
    POST "/enroll"  body {"name": "<str>"} ->
        - 400 if name empty.
        - Grab the current frame from `latest`. If None, 503.
        - Call pipeline.face.enroll_from_image(name, frame). (Guard: if
          pipeline.face is None / not available -> 503 with a clear message that
          ENABLE_FACE must be true.)
        - Return {ok, message, known_count}.
    GET "/known" -> return the list of unique enrolled names +
        counts (derive from pipeline.face.known_names, or [] if unavailable).
    Reuse the existing _jsonify + broadcast helpers as needed. The pipeline is
    already passed into make_app, so access the face module via pipeline.face.

(c) web UI — add an "Enroll a Face" panel:
    - A text input for the person's name + an "Enroll from Live View" button that
      POSTs /enroll and shows the returned message (success/failure).
    - Show the current known list from GET /known.
    - Update the Current Visitor card to display the identity NAME prominently and
      apply the existing known/unknown CSS classes (green border for known, amber
      for unknown). The card should show confidence when known.
    - Keep the whole UI vanilla JS, no CDN.

--- 7) Flip the flag ---
Set ENABLE_FACE = True in config.py so the feature is live.

====================================================================
PRIVACY NOTE (implement the honest version)
====================================================================
Enrollment saves the source photo under data/known_faces/<Name>/ for now (dev
convenience). In code comments, note that a production build would store only the
embedding (the known_faces DB table already exists for this). You MAY, if
straightforward, also persist each new embedding into the known_faces table via
the existing Database — but do it in a try/except so a DB hiccup never blocks
enrollment. This is optional; recognition must work from the in-memory list
regardless.

====================================================================
VERIFICATION — run these and report ACTUAL output
====================================================================
1. Install deps:  source .venv/bin/activate && pip install -r requirements.txt
   (First run will also download the buffalo_l model ~300MB — expect a pause.)
2. Syntax: python -m py_compile on every .py; fix all errors.
3. Start: python3 run.py — confirm the FaceModule loads (log shows "Loaded N
   known face(s) for M people") and the server starts. The app MUST still start
   even if insightface failed to import (graceful degradation) — verify by
   reasoning about the guard, and ensure no crash if known_faces is empty.
4. Enroll yourself:
     - Stand in front of the webcam, type your name in the Enroll panel, click
       "Enroll from Live View" -> expect ok:true and known_count increments.
     - OR: python3 enroll.py "YourName" --camera
5. Ring the doorbell (POST /trigger via the button):
     - With your face in view -> event identity.known=true, name=YourName,
       announcement "YourName is at the door.", card shows green.
     - With no known face (cover camera or use a stranger) -> identity.known=false,
       "An unknown visitor is at the door.", card shows amber.
   Paste both event JSONs.
6. Confirm history still works and snapshots still save.
7. Confirm the OLD Phase-1 routes still behave (/, /video, /history, /snapshot,
   /mode). Nothing from Phase 1 should regress.

====================================================================
GUARDRAILS
====================================================================
- Do not open a camera anywhere except accessai/camera.py (enroll --camera and
  the server both reuse it / the existing latest-frame holder).
- Do not remove or rename existing VisitorEvent fields or Database methods.
- Keep the app runnable if ENABLE_FACE were flipped back to False.
- CPU-only; no GPU calls. buffalo_l on CPU is fine for single-frame triggers.
- Match existing code style (docstrings explaining WHY, guarded imports, logging).

FIRST restate understanding + list files you'll create/modify. THEN build. THEN
run the verification and report real output, fixing any errors before finishing.
```

---

## After the agent finishes Phase 2, send me a report with:
1. Startup log showing FaceModule loaded (N faces / M people).
2. The enroll flow result (`/enroll` response or `enroll.py` output).
3. Two `/trigger` event JSONs — one **known** (your name) and one **unknown**.
4. Confirmation that first-run model download completed and the match threshold
   behaved (any false accept/reject you noticed; did you tune FACE_MATCH_THRESHOLD?).
5. Any errors hit + fixes, and confirmation Phase 1 routes didn't regress.

Then I'll give you the **very detailed Phase 3 prompt** (Object & Scene Detection
with YOLOv8 + the Context/Intent engine).
