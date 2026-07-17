"""
FastAPI server - exposes the pipeline to the web dashboard (and later the
Flutter app / ESP32 client).

Routes:
    GET  /                    -> dashboard (index.html)
    GET  /video               -> MJPEG stream of the live camera
    POST /trigger             -> simulate a doorbell press (creates an event)
    GET  /history?limit=N     -> recent events
    POST /history/clear       -> delete ALL visit events + their snapshots
    GET  /event/{event_id}    -> one event
    POST /event/{id}/delete   -> delete one visit event + its snapshot
    GET  /snapshot/{event_id} -> jpeg snapshot for an event
    POST /enroll              -> enroll a face from the live frame (Phase 2)
    POST /enroll_upload       -> enroll a person from uploaded photo(s) (Phase 13)
    POST /known/delete        -> delete a known person (photos+embeddings) (P13)
    GET  /known_photo/{name}  -> representative photo thumbnail for a person (P13)
    GET  /known               -> list of enrolled people + counts (Phase 2/13)
    GET  /vlm_status          -> cloud VLM wiring (masked keys, model) (Phase 6)
    GET  /speech_status       -> speech recognition capabilities (Phase 7)
    POST /transcribe          -> transcribe an uploaded WAV (Phase 7)
    GET  /translate_status    -> translation backend + target language (Phase 8)
    POST /translate           -> translate a text string (Phase 8)
    POST /user_language       -> change the user's target language live (Phase 8)
    GET  /reid_status         -> re-ID backend + gallery size (Phase 9)
    GET  /suggestions         -> open "save this visitor?" prompts (Phase 9)
    POST /suggestions/confirm -> promote a clustered unknown to a known face (P9)
    POST /suggestions/dismiss -> dismiss a suggestion (Phase 9)
    POST /reply               -> speak a typed reply at the door (Phase 4)
    GET/POST /mode            -> read / set accessibility mode (drives TTS on/off)
    POST /listen              -> push-to-talk voice command (parse+act+speak) (P10)
    POST /ask                 -> free-form question about the live frame -> VLM (P16)
    GET  /wakeword_status     -> always-on wake-word listener state (Phase 10)
    POST /wakeword/{on|off}   -> start/stop the always-on listener (opt-in) (P10)
    GET  /status              -> central health: modules + flags + torch (Phase 10)
    POST /ring                -> hardware doorbell webhook (optional JPEG) (P10)
    WS   /events              -> pushes new VisitorEvents live
"""

import asyncio
import os
import threading
import time

import cv2
import numpy as np
from fastapi import (FastAPI, WebSocket, WebSocketDisconnect, HTTPException,
                     Body, UploadFile, File, Form, Request)
from fastapi.responses import (
    FileResponse, StreamingResponse, JSONResponse, HTMLResponse, Response,
)
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

from . import voice_commands
from .face_module import is_safe_person_name


class LatestFrame:
    """Thread-safe holder for the newest camera frame."""

    def __init__(self):
        self._lock = threading.Lock()
        self._frame = None

    def set(self, frame) -> None:
        with self._lock:
            self._frame = frame

    def get(self):
        with self._lock:
            return None if self._frame is None else self._frame.copy()


# Valid accessibility modes, kept here so both /mode routes agree.
_VALID_MODES = ("blind", "deaf", "both")


def make_app(*, pipeline, latest: LatestFrame, db, web_dir: str,
             history_dir: str, mode: str = "both",
             access=None, tts=None, speech=None, wakeword=None, cfg=None,
             wakeword_command_seconds: int = 4,
             visitor_listen_seconds: int = 6) -> FastAPI:
    app = FastAPI(title="AccessAI")

    # Phase 16: allow the Flutter app's WEB target (flutter run -d chrome) and any
    # other browser origin on the LAN to call these routes cross-origin. The
    # native Android build talks over dio and doesn't need CORS, but a permissive
    # policy here is harmless for a LAN appliance and unblocks quick web checks.
    # Additive only - it does not alter any existing route's behaviour.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Accessibility mode lives in memory (persisted later). Keep it in sync with
    # the accessibility engine so toggling the mode turns speech on/off live.
    start_mode = access.mode if access is not None else \
        (mode if mode in _VALID_MODES else "both")
    state = {"mode": start_mode}

    # --- Static web dashboard ------------------------------------------------
    if os.path.isdir(web_dir):
        app.mount("/static", StaticFiles(directory=web_dir), name="static")

    # --- Phase 14: mobile PWA (served alongside the desktop dashboard) --------
    # The app lives in web/app/. Explicit routes for the entrypoint, manifest, and
    # service worker (correct MIME + SW scope) are declared BEFORE the catch-all
    # static mount so they take precedence; the mount then serves app.js / app.css
    # / icons/*. The desktop dashboard at / is untouched.
    web_app_dir = os.path.join(web_dir, "app")

    def _app_file(name, media_type=None, headers=None):
        path = os.path.join(web_app_dir, name)
        if not os.path.exists(path):
            raise HTTPException(404, f"{name} not found")
        return FileResponse(path, media_type=media_type, headers=headers or {})

    @app.get("/app", response_class=HTMLResponse)
    @app.get("/app/", response_class=HTMLResponse)
    async def app_index():
        index = os.path.join(web_app_dir, "index.html")
        if not os.path.exists(index):
            return HTMLResponse(
                "<h1>AccessAI</h1><p>The mobile app files are missing at "
                f"{web_app_dir}.</p>")
        return FileResponse(index)

    @app.get("/app/manifest.webmanifest")
    async def app_manifest():
        return _app_file("manifest.webmanifest",
                         media_type="application/manifest+json")

    @app.get("/app/sw.js")
    async def app_sw():
        # Served at the /app/ scope so the worker controls /app/*. The
        # Service-Worker-Allowed header lets it claim that scope; never cache the
        # SW file itself so updates take effect on reload.
        return _app_file("sw.js", media_type="text/javascript",
                         headers={"Service-Worker-Allowed": "/app/",
                                  "Cache-Control": "no-cache"})

    if os.path.isdir(web_app_dir):
        app.mount("/app", StaticFiles(directory=web_app_dir, html=True),
                  name="mobileapp")

    # --- WebSocket broadcast -------------------------------------------------
    clients: set[WebSocket] = set()
    clients_lock = asyncio.Lock()

    async def broadcast(payload: dict) -> None:
        async with clients_lock:
            dead = []
            for ws in clients:
                try:
                    await ws.send_json(payload)
                except Exception:
                    dead.append(ws)
            for ws in dead:
                clients.discard(ws)

    # Thread-safe broadcast bridge (Phase 10). The always-on wake-word listener
    # runs in its OWN thread (outside the event loop), so it can't await
    # broadcast() directly. We capture the running loop at startup and let the
    # wake callback schedule a broadcast onto it. If the loop isn't up yet, the
    # push is simply skipped - the spoken answer still happens regardless.
    _loop_holder = {}

    @app.on_event("startup")
    async def _capture_loop():
        _loop_holder["loop"] = asyncio.get_running_loop()

    def broadcast_threadsafe(payload: dict) -> None:
        loop = _loop_holder.get("loop")
        if loop is None:
            return
        try:
            asyncio.run_coroutine_threadsafe(broadcast(payload), loop)
        except Exception as e:                            # pragma: no cover
            print(f"[Server] broadcast_threadsafe failed: {e}")

    app.state.broadcast_threadsafe = broadcast_threadsafe

    # --- Routes --------------------------------------------------------------
    @app.get("/", response_class=HTMLResponse)
    async def root():
        index = os.path.join(web_dir, "index.html")
        if not os.path.exists(index):
            return HTMLResponse(
                "<h1>AccessAI</h1><p>Server is running, but the dashboard files "
                f"are missing at {web_dir}.</p>"
            )
        return FileResponse(index)

    @app.get("/video")
    def video():
        def gen():
            while True:
                frame = latest.get()
                if frame is None:
                    time.sleep(0.05)
                    continue
                ok, buf = cv2.imencode(".jpg", frame,
                                       [cv2.IMWRITE_JPEG_QUALITY, 80])
                if not ok:
                    continue
                data = buf.tobytes()
                yield (b"--frame\r\n"
                       b"Content-Type: image/jpeg\r\n"
                       b"Content-Length: " + str(len(data)).encode() + b"\r\n\r\n"
                       + data + b"\r\n")
                time.sleep(1 / 20)   # ~20 fps
        return StreamingResponse(
            gen(), media_type="multipart/x-mixed-replace; boundary=frame"
        )

    @app.post("/trigger")
    async def trigger():
        frame = latest.get()
        if frame is None:
            # Headless / no-webcam fallback: use a blank gray frame so the
            # pipeline, snapshot, and history still work. Never 503 forever.
            print("[Server] No camera frame available; using blank gray frame.")
            frame = np.full((720, 1280, 3), 127, dtype=np.uint8)

        loop = asyncio.get_event_loop()
        ev = await loop.run_in_executor(
            None, lambda: pipeline.run_once(frame, trigger="doorbell")
        )
        payload = {"type": "event", "event": _jsonify(ev.to_dict())}
        await broadcast(payload)
        return JSONResponse(payload["event"])

    @app.get("/history")
    def history(limit: int = 50):
        return JSONResponse(db.recent_events(limit=limit))

    @app.get("/event/{event_id}")
    def event(event_id: str):
        e = db.get_event(event_id)
        if not e:
            raise HTTPException(404, "event not found")
        return JSONResponse(e)

    # --- Visit-history removal (dashboard delete / clear all) ----------------
    def _safe_unlink_snapshot(event_id: str, stored_path: str = "") -> None:
        """Delete an event's snapshot .jpg, but ONLY if it resolves inside
        history_dir. Guards against path traversal and never raises (a missing
        file is fine). Tries both the stored path and history_dir/<id>.jpg."""
        base = os.path.realpath(history_dir)
        candidates = []
        if stored_path:
            candidates.append(stored_path)
        candidates.append(os.path.join(history_dir, f"{event_id}.jpg"))
        for cand in candidates:
            try:
                real = os.path.realpath(cand)
                if (real == base or real.startswith(base + os.sep)) \
                        and os.path.isfile(real):
                    os.remove(real)
            except Exception as e:                        # pragma: no cover
                print(f"[Server] snapshot cleanup skipped for {event_id}: {e}")

    @app.post("/event/{event_id}/delete")
    async def event_delete(event_id: str):
        """Delete ONE visit event (DB row + snapshot). 404 if unknown."""
        if not is_safe_person_name(event_id):
            raise HTTPException(404, "event not found")
        loop = asyncio.get_event_loop()
        path = await loop.run_in_executor(None, lambda: db.delete_event(event_id))
        if path is None:
            raise HTTPException(404, "event not found")
        _safe_unlink_snapshot(event_id, path)
        await broadcast({"type": "history_update"})
        return JSONResponse({"deleted": event_id})

    @app.post("/history/clear")
    async def history_clear():
        """Delete ALL visit events + their snapshots. Known people and re-ID
        visitor memory are left untouched."""
        loop = asyncio.get_event_loop()
        paths = await loop.run_in_executor(None, db.clear_events)
        for p in paths:
            # event_id is unknown here; pass the stored path (still fenced to
            # history_dir by _safe_unlink_snapshot). Use its stem as the id hint.
            stem = os.path.splitext(os.path.basename(p))[0] if p else ""
            _safe_unlink_snapshot(stem, p)
        await broadcast({"type": "history_update"})
        return JSONResponse({"cleared": len(paths)})

    @app.get("/snapshot/{event_id}")
    def snapshot(event_id: str):
        e = db.get_event(event_id)
        p = e.get("snapshot_path") if e else ""
        if not p or not os.path.exists(p):
            alt = os.path.join(history_dir, f"{event_id}.jpg")
            if os.path.exists(alt):
                p = alt
            else:
                raise HTTPException(404, "snapshot not found")
        return FileResponse(p, media_type="image/jpeg")

    @app.post("/enroll")
    async def enroll(payload: dict = Body(...)):
        name = (payload.get("name") or "").strip()
        if not name:
            raise HTTPException(400, "name is required")
        face = getattr(pipeline, "face", None)
        if face is None or not face.available():
            raise HTTPException(
                503, "Face recognition is not available. Set ENABLE_FACE=True "
                     "in config.py (and install insightface) and restart.")
        frame = latest.get()
        if frame is None:
            raise HTTPException(503, "No camera frame available yet.")
        # Run enrollment off the event loop (InsightFace inference is blocking).
        loop = asyncio.get_event_loop()
        ok, message = await loop.run_in_executor(
            None, lambda: face.enroll_from_image(name, frame))
        return {"ok": ok, "message": message,
                "known_count": len(face.known_names)}

    @app.get("/known")
    def known():
        face = getattr(pipeline, "face", None)
        if face is None or not face.available():
            return {"people": [], "known_count": 0}
        # Phase 13: richer list (name + photo count + thumbnail URL). Each entry
        # keeps a `count` alias so older clients that read p.count still work.
        return {"people": face.list_people(),
                "known_count": len(face.known_names)}

    # --- Phase 13: upload-photo enrollment + known-people management ---------
    @app.post("/enroll_upload")
    async def enroll_upload(name: str = Form(...),
                            files: list[UploadFile] = File(...)):
        """Enroll a known person from one or MORE uploaded photos.

        multipart/form-data: `name` + one or more image `files`. Each photo's
        face embedding is extracted and added to the recognition gallery
        immediately (no restart) and persisted. Non-image files are skipped
        gracefully (never a 500). 400 on empty name / no files; 503 when face
        recognition is off."""
        person = (name or "").strip()
        if not person:
            raise HTTPException(400, "name is required")
        if not is_safe_person_name(person):
            raise HTTPException(400, "name may not contain '/', '\\', or '..'")
        face = getattr(pipeline, "face", None)
        if face is None or not face.available():
            raise HTTPException(
                503, "Face recognition is not available. Set ENABLE_FACE=True "
                     "in config.py (and install insightface) and restart.")
        if not files:
            raise HTTPException(400, "at least one photo file is required")

        # Decode each upload to a BGR image off the event loop. A file that isn't
        # a decodable image becomes None -> enroll_from_files records a clean skip.
        images = []
        for uf in files:
            data = await uf.read()
            img = None
            if data:
                try:
                    arr = np.frombuffer(data, dtype=np.uint8)
                    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                except Exception:
                    img = None
            images.append(img)

        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None, lambda: face.enroll_from_files(person, images))
        await broadcast({"type": "known_update"})
        return JSONResponse(result)

    @app.post("/known/delete")
    async def known_delete(payload: dict = Body(...)):
        """Delete a known person (in-memory gallery + saved photos + DB rows)."""
        name = (payload.get("name") or "").strip()
        if not name:
            raise HTTPException(400, "name is required")
        if not is_safe_person_name(name):
            raise HTTPException(400, "name may not contain '/', '\\', or '..'")
        face = getattr(pipeline, "face", None)
        if face is None or not face.available():
            raise HTTPException(
                503, "Face recognition is not available. Set ENABLE_FACE=True "
                     "in config.py and restart.")
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None, lambda: face.remove_person(name))
        await broadcast({"type": "known_update"})
        return JSONResponse(result)

    @app.get("/known_photo/{name}")
    def known_photo(name: str):
        """Return a representative saved photo for `name` (thumbnail), 404 if none."""
        person = (name or "").strip()
        if not is_safe_person_name(person):
            raise HTTPException(404, "not found")
        face = getattr(pipeline, "face", None)
        if face is None:
            raise HTTPException(404, "not found")
        path = face.sample_photo_path(person)
        if not path or not os.path.exists(path):
            raise HTTPException(404, "no photo for this person")
        return FileResponse(path, media_type="image/jpeg")

    @app.get("/vlm_status")
    def vlm_status():
        """Phase 6: report the cloud VLM's wiring WITHOUT ever leaking a key.

        Keys are masked to last-4 by the module. Safe to expose to the dashboard
        so a user can see at a glance whether scene description is live.
        """
        vlm = getattr(pipeline, "vlm", None)
        if vlm is None:
            return {"enabled": bool(getattr(pipeline, "vlm_enabled", False)),
                    "available": False, "reason": "VLM not built (ENABLE_VLM off)"}
        st = vlm.status()
        st["enabled"] = bool(getattr(pipeline, "vlm_enabled", False))
        st["only_for_unknown"] = bool(getattr(pipeline, "vlm_only_for_unknown",
                                              True))
        return st

    @app.get("/speech_status")
    def speech_status():
        """Phase 7: report speech-recognition capabilities for the status pill."""
        speech = getattr(pipeline, "speech", None)
        if speech is None:
            return {"enabled": bool(getattr(pipeline, "speech_enabled", False)),
                    "available": False}
        caps = speech.capabilities()
        return {"enabled": bool(getattr(pipeline, "speech_enabled", False)),
                "available": speech.available(),
                "model": getattr(speech, "model_name", ""),
                **caps}

    @app.post("/transcribe")
    async def transcribe(file: UploadFile = File(...)):
        """Phase 7: transcribe an uploaded WAV - lets speech be tested without a
        mic. Returns {text, language}. 503 if speech recognition is unavailable."""
        speech = getattr(pipeline, "speech", None)
        if speech is None or not speech.available():
            raise HTTPException(
                503, "Speech recognition is not available. Set ENABLE_SPEECH=True "
                     "in config.py (and install openai-whisper) and restart.")
        data = await file.read()
        if not data:
            raise HTTPException(400, "empty upload")
        loop = asyncio.get_event_loop()
        text, lang = await loop.run_in_executor(
            None, lambda: speech.transcribe_wav(data))
        return {"text": text, "language": lang}

    @app.get("/translate_status")
    def translate_status():
        """Phase 8: report the translation backend + target language for the pill."""
        tr = getattr(pipeline, "translate", None)
        enabled = bool(getattr(pipeline, "translate_enabled", False))
        if tr is None:
            return {"enabled": enabled, "backend": "none", "available": False,
                    "user_language": "en"}
        st = tr.status()
        st["enabled"] = enabled
        return st

    @app.post("/translate")
    async def translate(payload: dict = Body(...)):
        """Phase 8: translate a text string (lets translation be tested without
        speech). Returns {translated}. Falls back to the original text on any
        failure (graceful passthrough), so this never 500s on missing keys."""
        tr = getattr(pipeline, "translate", None)
        if tr is None or not getattr(pipeline, "translate_enabled", False):
            raise HTTPException(
                503, "Translation is not available. Set ENABLE_TRANSLATE=True in "
                     "config.py and restart.")
        text = (payload.get("text") or "").strip()
        if not text:
            raise HTTPException(400, "text is required")
        src = (payload.get("src") or "").strip()
        target = (payload.get("target") or "").strip() or None
        loop = asyncio.get_event_loop()
        out = await loop.run_in_executor(
            None, lambda: tr.translate(text, src_lang=src, target_lang=target))
        return {"translated": out, "backend": tr.backend_name(),
                "available": tr.available()}

    @app.post("/user_language")
    async def user_language(payload: dict = Body(...)):
        """Phase 8: change the user's target language live. Updates the injected
        TranslateModule (the pipeline reads its user_language) AND persists the
        choice to data/user_language.txt so it survives a restart (loaded back in
        run.py at boot). Persistence is best-effort: a write failure never blocks
        the live change."""
        lang = (payload.get("lang") or "").strip()
        if not lang:
            raise HTTPException(400, "lang is required")
        tr = getattr(pipeline, "translate", None)
        if tr is None:
            raise HTTPException(503, "Translation is not available.")
        tr.set_user_language(lang)
        # Persist next to the DB (data/), derived from history_dir's parent so we
        # don't need to import config here. Sanitise to a short code first.
        code = "".join(c for c in tr.user_language if c.isalnum() or c in "-_")[:16]
        try:
            data_dir = os.path.dirname(os.path.realpath(history_dir))
            with open(os.path.join(data_dir, "user_language.txt"), "w",
                      encoding="utf-8") as fh:
                fh.write(code)
        except Exception as e:                                # best-effort only
            print(f"[server] could not persist user_language: {e}")
        return {"user_language": tr.user_language,
                "user_language_name": tr.lang_name(tr.user_language)}

    @app.get("/reid_status")
    def reid_status():
        """Phase 9: report the re-ID backend + gallery size for the status pill."""
        reid = getattr(pipeline, "reid", None)
        enabled = bool(getattr(pipeline, "reid_enabled", False))
        if reid is None:
            return {"enabled": enabled, "available": False,
                    "backend": "none", "gallery_size": 0, "placeholder": False}
        return {"enabled": enabled, "available": reid.available(),
                "backend": reid.backend_name(),
                "gallery_size": reid.gallery_size(),
                "placeholder": reid.is_placeholder()}

    @app.get("/suggestions")
    async def suggestions():
        """Phase 9: open 'save this visitor?' prompts from auto-enroll clustering.

        Recomputes lazily (DBSCAN) inside suggestions(), so this is the natural
        refresh point for the UI. Runs off the event loop (clustering is CPU)."""
        ae = getattr(pipeline, "autoenroll", None)
        if ae is None or not ae.available():
            return {"suggestions": []}
        loop = asyncio.get_event_loop()
        items = await loop.run_in_executor(None, ae.suggestions)
        return {"suggestions": items}

    @app.post("/suggestions/confirm")
    async def suggestions_confirm(payload: dict = Body(...)):
        """Phase 9: promote a clustered unknown to a KNOWN face under `name`."""
        ae = getattr(pipeline, "autoenroll", None)
        if ae is None or not ae.available():
            raise HTTPException(503, "Auto-enrollment is not available.")
        cluster_id = (payload.get("cluster_id") or "").strip()
        name = (payload.get("name") or "").strip()
        if not cluster_id or not name:
            raise HTTPException(400, "cluster_id and name are required")
        loop = asyncio.get_event_loop()
        ok = await loop.run_in_executor(None, lambda: ae.confirm(cluster_id, name))
        face = getattr(pipeline, "face", None)
        known_count = len(face.known_names) if face is not None else 0
        # Nudge any connected dashboards to refresh their suggestion list.
        await broadcast({"type": "suggestions_update"})
        return {"ok": bool(ok), "name": name, "known_count": known_count}

    @app.post("/suggestions/dismiss")
    async def suggestions_dismiss(payload: dict = Body(...)):
        """Phase 9: dismiss a suggestion without enrolling."""
        ae = getattr(pipeline, "autoenroll", None)
        if ae is None or not ae.available():
            raise HTTPException(503, "Auto-enrollment is not available.")
        cluster_id = (payload.get("cluster_id") or "").strip()
        if not cluster_id:
            raise HTTPException(400, "cluster_id is required")
        loop = asyncio.get_event_loop()
        ok = await loop.run_in_executor(None, lambda: ae.dismiss(cluster_id))
        await broadcast({"type": "suggestions_update"})
        return {"ok": bool(ok)}

    @app.post("/reply")
    async def reply(payload: dict = Body(...)):
        """Two-way reply: speak a typed message at the door (Phase 4)."""
        text = (payload.get("text") or "").strip()
        if not text:
            raise HTTPException(400, "text is required")
        spoken = False
        if access is not None:
            spoken = bool(access.speak_text(text))
        elif tts is not None:
            spoken = bool(tts.speak(text))
        engine = tts.engine_name() if tts is not None else "none"
        return {"ok": True, "spoken": spoken, "engine": engine, "text": text}

    # --- Phase 14: phone-side speech + text/voice commands (mobile app) -------
    @app.get("/speak_audio")
    async def speak_audio(text: str = ""):
        """Synthesize `text` with the natural Kokoro voice and return WAV bytes for
        the PHONE to play (mobile Blind-mode speech). Does NOT speak on the server.
        Clean-JSON 503 when no synth backend is available -> the app falls back to
        the browser Web Speech API. Runs synthesis OFF the announcement worker."""
        text = (text or "").strip()
        if not text:
            raise HTTPException(400, "text is required")
        if tts is None or not hasattr(tts, "synth_wav_bytes"):
            raise HTTPException(503, "TTS synthesis is not available.")
        loop = asyncio.get_event_loop()
        wav, _sr = await loop.run_in_executor(
            None, lambda: tts.synth_wav_bytes(text))
        if not wav:
            raise HTTPException(
                503, "Could not synthesize audio; use the browser voice fallback.")
        return Response(content=wav, media_type="audio/wav",
                        headers={"Cache-Control": "no-store"})

    @app.post("/command")
    async def command(payload: dict = Body(...)):
        """Text/voice command from the phone. Reuses the existing voice_commands
        parser + handler (same intents as push-to-talk) and returns {intent, answer}.
        The phone speaks the answer via /speak_audio. Never 500s on an unknown
        command - it returns a helpful fallback sentence."""
        text = (payload.get("text") or "").strip()
        if not text:
            raise HTTPException(400, "text is required")
        parsed = voice_commands.parse_command(text)
        intent = parsed.get("intent", "unknown")
        cmd_args = parsed.get("args", {})
        loop = asyncio.get_event_loop()
        answer = await loop.run_in_executor(
            None, lambda: voice_commands.handle_command(
                intent, cmd_args, pipeline=pipeline, db=db, latest=latest,
                access=access))
        # Nudge open dashboards (mirrors /listen's "voice" broadcast shape).
        await broadcast({"type": "voice", "intent": intent, "answer": answer,
                         "text": text})
        return {"intent": intent, "answer": answer, "text": text}

    @app.post("/ask")
    async def ask(payload: dict = Body(...)):
        """Phase 16: free-form question about the CURRENT camera frame, answered by
        the VLM (e.g. 'what colour is their dress', 'what is he doing now').

        ADDITIVE - does not touch /command or any existing route. Returns a short,
        hedged {answer}. 503 (clean JSON, never a stack trace) when the VLM is
        disabled or has no keys, mirroring /translate. Optionally speaks the answer
        when speak=true so a Blind user hears it hands-free."""
        question = (payload.get("question") or payload.get("text") or "").strip()
        if not question:
            raise HTTPException(400, "question is required")
        vlm = getattr(pipeline, "vlm", None)
        vlm_on = bool(getattr(pipeline, "vlm_enabled", False))
        if vlm is None or not vlm_on or not vlm.available():
            raise HTTPException(
                503, "Visual question answering is not available. Set ENABLE_VLM="
                     "True and provide GITHUB_MODELS_KEYS in .env, then restart.")
        loop = asyncio.get_event_loop()
        answer = await loop.run_in_executor(
            None, lambda: voice_commands._answer_scene(
                pipeline, latest, db, question))
        # Optional hands-free readback (Blind mode) - best-effort, never blocks.
        if bool(payload.get("speak")) and access is not None and answer:
            try:
                await loop.run_in_executor(None, lambda: access.speak_text(answer))
            except Exception as e:                        # pragma: no cover
                print(f"[server] /ask speak failed: {e}")
        await broadcast({"type": "voice", "intent": "ask_scene",
                         "answer": answer, "text": question})
        return {"question": question, "answer": answer}

    @app.get("/mode")
    def get_mode():
        return {"mode": state["mode"]}

    @app.post("/mode")
    async def set_mode(payload: dict = Body(...)):
        m = payload.get("mode")
        if m not in _VALID_MODES:
            raise HTTPException(400, "mode must be blind|deaf|both")
        state["mode"] = m
        # Drive the accessibility engine so speaking actually toggles live.
        if access is not None:
            access.set_mode(m)
        return {"mode": m}

    # --- Phase 11: natural voice picker -------------------------------------
    @app.get("/voices")
    def voices():
        """List selectable voices (offline Kokoro + online edge) with availability,
        plus the currently active voice + engine. Powers the dashboard picker."""
        if tts is None:
            return {"voices": [], "current": "none", "engine": "none",
                    "available": False}
        return {"voices": tts.list_voices(),
                "current": tts.current_voice(),
                "engine": tts.engine_name(),
                "available": tts.available(),
                "backends": tts.backends()}

    @app.post("/voice")
    async def set_voice(payload: dict = Body(...)):
        """Switch the active voice live, e.g. {"id":"kokoro:af_bella"}.

        On success we SPEAK a short confirmation in the NEW voice so the user
        hears the change. Returns clean JSON either way (never a stack trace):
        an unavailable/offline target yields {ok:false, message:...} and keeps the
        current voice - it does not 500."""
        if tts is None:
            raise HTTPException(503, "TTS is not available.")
        vid = (payload.get("id") or "").strip()
        if not vid:
            raise HTTPException(400, "id is required, e.g. 'kokoro:af_heart'")
        ok, message = tts.set_voice(vid)
        spoke = False
        if ok:
            # Speak the confirmation in the newly-selected voice (worker thread).
            spoke = bool(tts.speak("Voice changed. This is how I sound now."))
        return {"ok": bool(ok), "message": message,
                "engine": tts.engine_name(), "voice": tts.current_voice(),
                "spoke": spoke}

    @app.get("/tts_status")
    def tts_status():
        """Phase 11: TTS engine + voice + per-backend availability for the pill."""
        if tts is None:
            return {"enabled": False, "available": False, "engine": "none",
                    "voice": "none", "kokoro": False, "edge": False,
                    "pyttsx3": False}
        b = tts.backends()
        return {"enabled": bool(getattr(tts, "_enabled", False)),
                "available": tts.available(),
                "engine": tts.engine_name(),
                "voice": tts.current_voice(),
                "kokoro": b["kokoro"], "edge": b["edge"],
                "pyttsx3": b["pyttsx3"]}

    # --- Phase 10: voice commands (push-to-talk) ----------------------------
    @app.post("/listen")
    async def listen(file: UploadFile = File(None)):
        """Push-to-talk voice command. Records one command from the mic (or uses
        an uploaded WAV), parses it, acts, and SPEAKS the answer. Always works
        even when the always-on wake word is off. Returns what was heard + the
        spoken reply. Clean JSON 503 when speech recognition is unavailable."""
        if speech is None or not speech.available():
            raise HTTPException(
                503, "Speech recognition is not available. Set ENABLE_SPEECH=True "
                     "in config.py (and install openai-whisper) and restart.")
        wav_bytes = None
        if file is not None:
            wav_bytes = await file.read()
            if not wav_bytes:
                wav_bytes = None
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None, lambda: voice_commands.run_voice_interaction(
                speech=speech, pipeline=pipeline, db=db, latest=latest,
                access=access, seconds=wakeword_command_seconds,
                wav_bytes=wav_bytes))
        await broadcast({"type": "voice", **result})
        return JSONResponse(result)

    # --- Phase 12: two-way "Hear Visitor" (OPT-IN visitor audio) -------------
    @app.post("/hear_visitor")
    async def hear_visitor():
        """Record the VISITOR for a few seconds ON DEMAND, transcribe + translate
        it, and attach the result to the most recent visitor event.

        This is DELIBERATELY separate from the doorbell: a plain /trigger records
        NOTHING. Audio is captured only when the user presses "Hear Visitor",
        making two-way communication explicit and consent-based. It is also
        distinct from /listen, which captures the BLIND USER's own voice COMMANDS.

        Returns {transcript, translated, language, event_id}. Clean JSON 503 when
        speech recognition / the mic is unavailable; never 500s on a failure."""
        if speech is None or not speech.available():
            raise HTTPException(
                503, "Speech recognition is not available. Set ENABLE_SPEECH=True "
                     "in config.py (and install openai-whisper) and restart.")

        secs = int(visitor_listen_seconds or 6)
        loop = asyncio.get_event_loop()

        def _capture():
            audio = speech.record(secs)
            if audio is None:
                return None, "", ""          # mic unavailable / capture failed
            if speech.use_vad and not speech.has_speech(audio):
                return "", "", ""            # silence -> empty transcript, no error
            text, lang = speech.transcribe(audio)
            return "captured", (text or ""), (lang or "")

        status, text, lang = await loop.run_in_executor(None, _capture)
        if status is None:
            raise HTTPException(
                503, "Could not capture audio (no microphone available).")

        # Translate into the user's language (fail-soft: fall back to the original).
        translated = ""
        tr = getattr(pipeline, "translate", None)
        if (text and tr is not None
                and getattr(pipeline, "translate_enabled", False)):
            target = getattr(tr, "user_language", "en")
            if (lang or "") != target:
                out = await loop.run_in_executor(
                    None, lambda: tr.translate(text, src_lang=lang,
                                               target_lang=target))
                if (out and out.strip() and out.strip() != text.strip()):
                    translated = out.strip()

        # Attach to the MOST RECENT event so the dashboard card + history show what
        # the visitor said. Standalone (no event yet) still returns the transcript.
        event_id = db.latest_event_id()
        if event_id:
            fields = {"speech_transcript": text, "language_detected": lang}
            if translated:
                fields["translated_transcript"] = translated
            await loop.run_in_executor(
                None, lambda: db.update_event_fields(event_id, **fields))

        await broadcast({"type": "visitor_speech", "text": text,
                         "translated": translated, "language": lang,
                         "event_id": event_id})
        return JSONResponse({"transcript": text, "translated": translated,
                             "language": lang, "event_id": event_id})

    @app.get("/wakeword_status")
    def wakeword_status():
        """Phase 10: report the always-on wake-word listener's state."""
        enabled = bool(getattr(cfg, "ENABLE_WAKEWORD", False)) if cfg else \
            (wakeword is not None)
        if wakeword is None:
            return {"enabled": enabled, "available": False, "running": False,
                    "model": "none", "placeholder": True,
                    "reason": "openWakeWord not built (ENABLE_WAKEWORD off or "
                              "package missing). Push-to-talk via /listen still works."}
        st = wakeword.status()
        st["enabled"] = enabled
        return st

    @app.post("/wakeword/{action}")
    async def wakeword_toggle(action: str):
        """Phase 10: start/stop the always-on listener at runtime (OPT-IN).

        The dashboard toggle hits this. Off by default: an open mic is a CPU +
        privacy choice the user makes deliberately. 503 (clean JSON) when the
        detector/mic isn't available - push-to-talk still works regardless."""
        if action not in ("on", "off"):
            raise HTTPException(400, "action must be 'on' or 'off'")
        if wakeword is None or not wakeword.available():
            raise HTTPException(
                503, "Always-on wake word is not available (openWakeWord or a mic "
                     "is missing). Use the push-to-talk 'Speak a command' button.")
        if action == "on":
            ok = wakeword.start()
        else:
            wakeword.stop()
            ok = True
        return {"ok": bool(ok), "running": wakeword.running(),
                "model": wakeword.model_name}

    # --- Phase 10: central health endpoint ----------------------------------
    @app.get("/status")
    def status():
        """One-stop health for every module + config flags + torch version.

        Powers the dashboard 'System Health' panel and the boot self-check. Never
        raises: each module is probed defensively. `state` is one of
        ok | placeholder | unavailable | off, so the UI can colour it."""
        return JSONResponse(_collect_status())

    # --- Phase 10: hardware doorbell webhook (ESP32-CAM readiness) -----------
    @app.post("/ring")
    async def ring(request: Request):
        """Hardware webhook: an ESP32 (or any device) POSTs to ring the bell.

        Optionally accepts a raw JPEG body (the device's own capture); otherwise
        it uses the latest frame from the configured camera, or a blank frame if
        headless. Identical downstream path to /trigger, so it drives the exact
        same event pipeline + dashboard broadcast."""
        frame = None
        source = "latest-frame"
        try:
            body = await request.body()
        except Exception:
            body = b""
        if body:
            try:
                arr = np.frombuffer(body, dtype=np.uint8)
                img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                if img is not None:
                    frame = img
                    source = "posted-jpeg"
            except Exception as e:
                print(f"[Server] /ring JPEG decode failed, using camera: {e}")
        if frame is None:
            frame = latest.get()
        if frame is None:
            print("[Server] /ring: no frame available; using blank gray frame.")
            frame = np.full((720, 1280, 3), 127, dtype=np.uint8)
            source = "blank"
        loop = asyncio.get_event_loop()
        ev = await loop.run_in_executor(
            None, lambda: pipeline.run_once(frame, trigger="ring"))
        payload = {"type": "event", "event": _jsonify(ev.to_dict())}
        await broadcast(payload)
        return JSONResponse({"ok": True, "frame_source": source,
                             "event": payload["event"]})

    # ------------------------------------------------------------------
    def _safe(fn, default=None):
        try:
            return fn()
        except Exception:
            return default

    def _mod(name, enabled, available, placeholder=False, detail=""):
        enabled = bool(enabled)
        available = bool(available)
        if not enabled:
            st = "off"
        elif not available:
            st = "unavailable"
        elif placeholder:
            st = "placeholder"
        else:
            st = "ok"
        return {"name": name, "enabled": enabled, "available": available,
                "placeholder": bool(placeholder), "state": st, "detail": detail}

    def _collect_status():
        torch_version = _safe(lambda: __import__("torch").__version__,
                              "not installed")
        modules = []

        face = getattr(pipeline, "face", None)
        modules.append(_mod(
            "face", getattr(pipeline, "face_enabled", False),
            face is not None and _safe(face.available, False),
            detail=(f"{len(face.known_names)} known" if face is not None else "")))

        vision = getattr(pipeline, "vision", None)
        modules.append(_mod(
            "vision", getattr(pipeline, "vision_enabled", False),
            vision is not None and _safe(vision.available, False),
            detail="YOLOv8 object detection"))

        anti = getattr(pipeline, "antispoof", None)
        anti_backend = _safe(lambda: anti.backend_name(), "") if anti else ""
        modules.append(_mod(
            "antispoof", getattr(pipeline, "antispoof_enabled", False),
            anti is not None and _safe(anti.available, False),
            placeholder=("heuristic" in (anti_backend or "").lower()),
            detail=anti_backend or "liveness check"))

        vlm = getattr(pipeline, "vlm", None)
        modules.append(_mod(
            "vlm", getattr(pipeline, "vlm_enabled", False),
            vlm is not None and _safe(vlm.available, False),
            detail="cloud scene description + OCR"))

        sp = getattr(pipeline, "speech", None)
        modules.append(_mod(
            "speech", getattr(pipeline, "speech_enabled", False),
            sp is not None and _safe(sp.available, False),
            detail=(f"Whisper '{getattr(sp, 'model_name', '')}'" if sp else "")))

        tr = getattr(pipeline, "translate", None)
        tr_backend = _safe(lambda: tr.backend_name(), "") if tr else ""
        modules.append(_mod(
            "translate", getattr(pipeline, "translate_enabled", False),
            tr is not None and _safe(tr.available, False),
            detail=tr_backend or "passthrough"))

        reid = getattr(pipeline, "reid", None)
        reid_ph = _safe(lambda: reid.is_placeholder(), False) if reid else False
        reid_backend = _safe(lambda: reid.backend_name(), "") if reid else ""
        modules.append(_mod(
            "reid", getattr(pipeline, "reid_enabled", False),
            reid is not None and _safe(reid.available, False),
            placeholder=bool(reid_ph),
            detail=(f"{reid_backend} ({_safe(reid.gallery_size, 0)} in gallery)"
                    if reid else "")))

        ae = getattr(pipeline, "autoenroll", None)
        modules.append(_mod(
            "autoenroll", getattr(pipeline, "autoenroll_enabled", False),
            ae is not None and _safe(ae.available, False),
            detail="DBSCAN face clustering"))

        # Phase 11: TTS shows the active engine + voice; a fall-back to the
        # robotic pyttsx3 (when the natural kokoro voice was requested but its
        # model is missing) is flagged as a placeholder so the panel goes amber.
        tts_engine = _safe(tts.engine_name, "none") if tts else "none"
        tts_voice = _safe(tts.current_voice, "none") if tts else "none"
        tts_fellback = bool(tts is not None and tts_engine == "pyttsx3"
                            and _safe(tts.available, False))
        modules.append(_mod(
            "tts", getattr(tts, "_enabled", tts is not None) if tts else False,
            tts is not None and _safe(tts.available, False),
            placeholder=tts_fellback,
            detail=(f"{tts_voice}"
                    + (" (robotic fallback - kokoro model missing)"
                       if tts_fellback else "")) if tts else "none"))

        ww_enabled = bool(getattr(cfg, "ENABLE_WAKEWORD", False)) if cfg else \
            (wakeword is not None)
        modules.append(_mod(
            "wakeword", ww_enabled,
            wakeword is not None and _safe(wakeword.available, False),
            placeholder=True,   # pretrained phrase, not a trained "Hey Access"
            detail=(f"{wakeword.model_name} "
                    f"({'running' if wakeword and wakeword.running() else 'idle'})"
                    if wakeword else "openWakeWord not built")))

        flags = {}
        if cfg is not None:
            for k in dir(cfg):
                if k.startswith("ENABLE_"):
                    flags[k] = bool(getattr(cfg, k))

        return {
            "app": "AccessAI",
            "phase": 10,
            "mode": state["mode"],
            "torch_version": torch_version,
            "voice_path": ("always-on+push-to-talk"
                           if (wakeword is not None
                               and _safe(wakeword.available, False))
                           else ("push-to-talk"
                                 if (speech is not None
                                     and _safe(speech.available, False))
                                 else "unavailable")),
            "wakeword_running": bool(wakeword.running()) if wakeword else False,
            "tts": {
                "engine": tts_engine,
                "voice": tts_voice,
                "backends": _safe(tts.backends, {}) if tts else {},
                "fellback_to_pyttsx3": tts_fellback,
            },
            "modules": modules,
            "flags": flags,
        }

    @app.websocket("/events")
    async def ws_events(ws: WebSocket):
        await ws.accept()
        async with clients_lock:
            clients.add(ws)
        try:
            while True:
                await asyncio.sleep(30)          # keep-alive ping
                await ws.send_json({"type": "ping"})
        except WebSocketDisconnect:
            pass
        except Exception:
            pass
        finally:
            async with clients_lock:
                clients.discard(ws)

    return app


def _jsonify(d):
    """Recursively replace tuples with lists so JSON serialization is happy."""
    if isinstance(d, dict):
        return {k: _jsonify(v) for k, v in d.items()}
    if isinstance(d, (list, tuple)):
        return [_jsonify(x) for x in d]
    return d
