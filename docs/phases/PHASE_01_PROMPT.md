# PHASE 1 PROMPT — Foundation

Copy EVERYTHING inside the fenced block below and paste it as your first message
to the Claude agent in VS Code (with an empty or fresh `AccessAI` folder open as
the workspace).

---

```
You are building Phase 1 of a 10-phase project called AccessAI — an AI-powered
accessibility doorbell for blind and deaf people. Build ONLY Phase 1 as described
below. Do not build later phases. Prioritise a clean, runnable foundation that
later phases plug into without restructuring.

====================================================================
PROJECT CONTEXT (read fully before coding)
====================================================================
AccessAI perceives a visitor on behalf of a blind or deaf user and communicates
it through the sense the user has. A normal doorbell only says "someone is here".
AccessAI will eventually say: "Rahul is at the front door. He is carrying a
parcel. He said, 'Package for you.'" — delivered as speech (Blind Mode) or large
text + two-way chat (Deaf Mode).

The full 10-phase plan is: (1) Foundation [THIS PHASE], (2) Face recognition,
(3) Object/scene detection + intent, (4) Accessibility output/TTS/Blind+Deaf,
(5) Anti-spoofing, (6) VLM scene description + OCR, (7) Speech recognition,
(8) Multi-language translation, (9) Re-ID + auto-enrollment, (10) Wake word +
hardening + ESP32/Flutter readiness.

Phase 1's ONLY job: build the skeleton that every later phase plugs into — the
data model, config, camera abstraction, database, a FastAPI backend with a web
dashboard, and a manual "Ring" trigger that creates and stores a (mostly empty)
visitor event with a snapshot. NO AI models yet.

====================================================================
TARGET ENVIRONMENT (must work here)
====================================================================
- OS: Linux (Ubuntu). Shell: bash.
- Python: 3.12 (use a venv named .venv).
- CPU-only. No GPU assumptions.
- Do NOT add piper-tts (its dependency piper-phonemize has no Python 3.12 wheel
  and will break `pip install`). No TTS at all in Phase 1.
- Keep dependencies minimal in Phase 1 — only what the skeleton needs.

====================================================================
ARCHITECTURE RULES (these hold for all 10 phases — obey strictly)
====================================================================
1. THE VISITOR EVENT IS THE SPINE. One dataclass (accessai/visitor_event.py)
   flows through the whole system. Every module WRITES into it; every output
   READS from it. Design it in Phase 1 with fields reserved for ALL later phases
   (listed below) so future phases only fill fields — never restructure.
2. CAMERA ABSTRACTION: all frame access goes through accessai/camera.py, which
   accepts either an integer webcam index OR a URL string (MJPEG). Because
   OpenCV's VideoCapture accepts both, switching to an ESP32-CAM later is a
   ONE-LINE change in config.py (CAMERA_SOURCE). Never open a camera anywhere
   else.
3. CENTRAL CONFIG: accessai config lives in a single config.py at project root.
   All tunables and feature flags there. Later phases flip flags; Phase 1 sets
   them all to False/defaults.
4. GRACEFUL DEGRADATION: any component that could fail to import or initialise
   must be wrapped so the app still starts. Phase 1 has no heavy deps, but set
   the pattern: try/except import guards, an available() method where relevant,
   and print("[ModuleName] ...") logging.
5. RUNNABLE AT ALL TIMES: `python3 run.py` must start the server and show the
   dashboard even before any face is registered.
6. CONSERVATIVE LANGUAGE: any generated sentence about a visitor must be
   cautious ("likely", never "definitely"). Phase 1's default sentence is just
   "Someone is at the door."

====================================================================
EXACT PROJECT STRUCTURE TO CREATE
====================================================================
AccessAI/
├── config.py
├── run.py
├── requirements.txt
├── README.md
├── .gitignore
├── accessai/
│   ├── __init__.py
│   ├── camera.py
│   ├── visitor_event.py
│   ├── database.py
│   ├── pipeline.py
│   └── server.py
├── web/
│   ├── index.html
│   ├── app.js
│   └── style.css
└── data/                (created at runtime; gitignored)
    ├── known_faces/
    ├── history/
    └── accessai.db

====================================================================
FILE-BY-FILE SPECIFICATION
====================================================================

--- config.py ---
Single source of configuration. Define at least:
- BASE_DIR, DATA_DIR, KNOWN_FACES_DIR, HISTORY_DIR, WEB_DIR, DB_PATH (absolute,
  derived from BASE_DIR). Create the data directories at import time with
  os.makedirs(..., exist_ok=True).
- CAMERA_SOURCE = 0  (int webcam now; a URL string later for ESP32)
- FRAME_WIDTH = 1280, FRAME_HEIGHT = 720
- HOST = "0.0.0.0", PORT = 8000
- ACCESSIBILITY_MODE = "both"  ("blind" | "deaf" | "both")
- USER_LANGUAGE = "en"
- Feature flags, all False for now (reserved for later phases):
  ENABLE_FACE, ENABLE_VISION, ENABLE_ANTISPOOF, ENABLE_VLM, ENABLE_OCR,
  ENABLE_SPEECH, ENABLE_TRANSLATE, ENABLE_REID, ENABLE_AUTOENROLL,
  ENABLE_WAKEWORD.
- EVENT_COOLDOWN = 8, HISTORY_LIMIT = 200.
Add clear comments explaining the ESP32 one-line-swap idea on CAMERA_SOURCE.

--- accessai/visitor_event.py ---
Dataclasses using dataclasses + asdict. Define:
- Identity(known: bool=False, name: str="Unknown", confidence: float=0.0)
- DetectedObject(label: str, confidence: float, box: tuple=(0,0,0,0))
- VisitorEvent with fields reserved for ALL phases:
    event_id: str, timestamp: str, trigger: str="manual",
    identity: Identity, face_box: tuple=(0,0,0,0),
    spoof_score: float=1.0, is_spoof: bool=False,
    visitor_count: int=0, detected_objects: list[DetectedObject],
    carried_objects: list[str], scene_summary: str="", hazards: str="none",
    ocr_text: str="", speech_transcript: str="", language_detected: str="",
    translated_transcript: str="", reid_id: str|None=None,
    reid_seen_count: int=0, intent: str="unknown visitor",
    confidence: float=0.0, announcement_text: str="", snapshot_path: str="".
- to_dict() using asdict.
Add a module docstring explaining this is the system's spine.

--- accessai/camera.py ---
A Camera class wrapping cv2.VideoCapture:
- __init__(source=0, width=640, height=480)
- open() -> self (sets width/height, raises RuntimeError with a helpful message
  if the source can't be opened)
- read() -> BGR frame or None
- release()
- context manager (__enter__/__exit__)
Docstring must explain the int-index vs URL duality and the ESP32 one-line swap.

--- accessai/database.py ---
SQLite via SQLAlchemy 2.x (declarative_base, sessionmaker). Create tables now,
even ones later phases use, so the schema is stable:
- events: id, event_id (unique index), timestamp, trigger, identity_name,
  identity_known(int), identity_conf(float), is_spoof(int), spoof_score(float),
  visitor_count(int), carried_objects(Text JSON), scene_summary(Text),
  ocr_text(Text), speech_transcript(Text), language_detected(str),
  translated_transcript(Text), reid_id(str), reid_seen_count(int),
  intent(str), confidence(float), announcement_text(Text), snapshot_path(Text)
- known_faces: id, name, source_path, embedding(LargeBinary), created_at
- reid_gallery: id, reid_id, embedding(LargeBinary), last_seen, seen_count
- unknown_face_clusters: id, cluster_id, embedding(LargeBinary), event_id,
  created_at, suggested(int)
Database class methods:
- __init__(path): create engine sqlite:///path, create_all, sessionmaker.
- save_event(ev: VisitorEvent): persist (json.dumps lists).
- recent_events(limit) -> list[dict]  (newest first)
- get_event(event_id) -> dict | None
Provide a private _event_row_to_dict that reconstructs a nested identity dict and
json.loads the list fields.

--- accessai/pipeline.py ---
A Pipeline class that will grow each phase. Phase 1 version:
- __init__(db, history_dir) — stores refs. Constructor must ALSO accept optional
  keyword args that default to None so later phases can inject modules without
  changing call sites: face=None, vision=None, antispoof=None, vlm=None,
  ocr=None, speech=None, translate=None, reid=None, access=None, plus matching
  *_enabled bools defaulting False. Keep them as attributes even if unused now.
- run_once(frame_bgr, trigger="manual") -> VisitorEvent:
    * create a VisitorEvent with a unique event_id
      (evt_YYYYMMDD_HHMMSS_<6hexuuid>) and ISO timestamp.
    * Phase 1 sets no identity/objects (no models). visitor_count=0.
    * intent = "unknown visitor", announcement_text = "Someone is at the door."
    * save a snapshot jpg to history_dir named <event_id>.jpg via cv2.imwrite;
      set snapshot_path.
    * db.save_event(ev); return ev.
Add a helper _new_event_id(). Keep the structure obviously extensible with
TODO comments pointing at which phase fills which step (face → P2, objects → P3,
anti-spoof → P5, vlm/ocr → P6, speech → P7, translate → P8, reid → P9).

--- accessai/server.py ---
A make_app(*, pipeline, latest, db, web_dir, history_dir) -> FastAPI factory.
Include a LatestFrame thread-safe holder class (lock + get/set copy) in this
file. Routes:
- GET "/"                -> serve web/index.html (FileResponse); if missing,
                            return a minimal HTML saying the server is up.
- GET "/video"           -> MJPEG StreamingResponse
                            (multipart/x-mixed-replace; boundary=frame),
                            ~20 fps, JPEG quality 80, reading from `latest`.
- POST "/trigger"        -> grab latest frame (503 if none yet); run
                            pipeline.run_once in a thread executor
                            (run_in_executor) so it doesn't block the loop;
                            broadcast the event over the WebSocket; return the
                            event dict as JSON.
- GET "/history?limit=N" -> db.recent_events.
- GET "/event/{id}"      -> db.get_event (404 if missing).
- GET "/snapshot/{id}"   -> FileResponse of the event's snapshot jpg
                            (fallback to history_dir/<id>.jpg; 404 if missing).
- GET/POST "/mode"       -> get/set ACCESSIBILITY_MODE in memory (validate
                            blind|deaf|both).
- WS  "/events"          -> accept, register client, keep-alive ping every 30s,
                            clean up on disconnect. Provide an async broadcast()
                            that sends {"type":"event","event":...} to all
                            clients.
- Mount web_dir at "/static" via StaticFiles.
Ensure any tuples in the event dict are converted to lists before JSON
serialization (write a small recursive _jsonify helper).

--- run.py ---
Entry point:
- Build Database, Pipeline, LatestFrame.
- Start a daemon camera thread that opens accessai.camera.Camera(CAMERA_SOURCE,
  FRAME_WIDTH, FRAME_HEIGHT) and continuously writes frames to LatestFrame; on
  read failure or exception, log, release, wait 2s, and reconnect (never crash).
- Build the FastAPI app via make_app and run uvicorn on HOST:PORT.
- Print a clear "Open the dashboard: http://localhost:PORT" line.
- Clean shutdown on KeyboardInterrupt (stop the camera thread).

--- web/index.html + app.js + style.css ---
A clean dark-themed single-page dashboard:
- Header: title "AccessAI" + a Mode <select> (Both/Blind/Deaf) + a connection
  status pill.
- Live section: an <img id="video" src="/video"> showing the MJPEG stream, and a
  big "🔔 Ring Doorbell" button that POSTs /trigger.
- Current Visitor card: renders the latest event (who=Unknown for now, intent,
  timestamp, announcement_text). Different border colour for known/unknown/spoof
  (only unknown will occur in Phase 1, but include the CSS classes).
- A "Reply to visitor (Deaf Mode)" box: text input + button that POSTs /reply —
  BUT since there's no TTS in Phase 1, the endpoint may not exist yet; make the
  button gracefully show "TTS added in a later phase" if /reply returns 404.
- Visitor History list: fetch /history, show snapshot thumbnail (/snapshot/{id}),
  name, intent, timestamp, announcement.
- app.js: connect to ws://.../events, re-connect on close, update the current
  card and refresh history on new events; wire Ring, Mode, Reply, Refresh.
- No external CDN dependencies; plain vanilla JS + CSS.

--- requirements.txt ---
Pin versions known to work on Python 3.12 / CPU. Phase 1 needs ONLY:
  opencv-python, numpy, pillow, fastapi, uvicorn[standard], python-multipart,
  jinja2, SQLAlchemy.
Add a comment block listing deps that LATER phases will add (insightface,
onnxruntime, ultralytics, openai-whisper, silero-vad, transformers, torch,
paddleocr, torchreid, scikit-learn, openwakeword, pyttsx3) — commented out.
Explicitly note piper-tts is excluded (no 3.12 wheel).

--- .gitignore ---
Ignore: .venv/, __pycache__/, *.pyc, data/ (except keep the folder structure via
.gitkeep files in data/known_faces and data/history), *.db, model caches.

--- README.md ---
Quick start (venv + install + run), how to open the dashboard, and a note that
Phase 1 has no AI yet — it's the working skeleton. Include the ESP32 one-line
swap note and the Python 3.12 / no-piper note.

====================================================================
DELIVERABLES & VERIFICATION (you must run these before declaring done)
====================================================================
1. Create a fresh venv, install requirements, and confirm the app starts:
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   python3 run.py
2. Confirm http://localhost:8000 loads the dashboard and shows the live webcam
   (or, if no webcam device exists in this environment, the app must still start
   and the video simply shows nothing — it must NOT crash).
3. Confirm clicking "Ring Doorbell" creates an event, shows "Someone is at the
   door." in the Current Visitor card, saves a snapshot, and adds it to History.
4. Confirm GET /history returns the event JSON and GET /snapshot/{id} returns the
   image.
5. Run a syntax check on every .py file (python -m py_compile) and fix all
   errors.
6. If the webcam cannot be opened in your sandbox, still prove the pipeline by
   adding a tiny fallback: if no frame is available on /trigger, generate a
   blank 1280x720 gray frame so the event + snapshot still work, and log a
   warning. (Do NOT let /trigger 503 forever in a headless environment.)

====================================================================
CODING STYLE
====================================================================
- Every module starts with a docstring explaining WHY it exists.
- Use try/except import guards + print("[ModuleName] ...") logging.
- Type hints on public functions.
- No dead code, no placeholder functions that raise NotImplementedError — Phase 1
  must be fully functional as specified.
- Keep it CPU-only and dependency-light.

FIRST: restate your understanding in 3-4 bullets and list the files you will
create. THEN build everything. THEN run the verification steps and report the
actual output. Fix any errors before finishing.
```

---

## After the agent finishes Phase 1, send me a report containing:
1. Did `python3 run.py` start cleanly? Paste the startup log.
2. Did the dashboard load? Did the live video show?
3. Did "Ring Doorbell" create an event + snapshot + history entry? Paste the
   event JSON.
4. Any errors you hit and how they were resolved.
5. The final `requirements.txt` and the list of files created.

Then I'll give you the **very detailed Phase 2 prompt** (Face Recognition).
