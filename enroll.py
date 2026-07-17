"""
AccessAI - command-line face enroller (Phase 2).

Register a known person either from image files or from one live camera frame.
Recognition uses the SAME FaceModule the server uses, so anyone enrolled here is
recognised on the next "Ring".

Usage:
    # from one or more image files
    python3 enroll.py "Rahul" path/to/1.jpg path/to/2.jpg

    # grab a single frame from the configured camera (config.CAMERA_SOURCE)
    python3 enroll.py "Rahul" --camera

Notes:
- The camera is opened ONLY through accessai/camera.py (never cv2 directly here).
- ENABLE_FACE does not need to be True to enroll; we build a FaceModule directly.
"""

import sys
import time

import cv2

import config
from accessai.camera import Camera
from accessai.face_module import FaceModule


def _build_face() -> FaceModule:
    return FaceModule(known_dir=config.KNOWN_FACES_DIR,
                      threshold=config.FACE_MATCH_THRESHOLD,
                      model_name=config.FACE_MODEL_NAME,
                      det_size=config.FACE_DET_SIZE,
                      ctx_id=config.FACE_CTX_ID,
                      min_det_score=config.FACE_MIN_DET_SCORE)


def _grab_camera_frame():
    """Open the configured camera, read a few frames (let it warm up), return one."""
    cam = Camera(source=config.CAMERA_SOURCE,
                 width=config.FRAME_WIDTH, height=config.FRAME_HEIGHT)
    try:
        cam.open()
    except RuntimeError as e:
        print(f"[enroll] Camera error: {e}")
        return None
    frame = None
    try:
        # Read a handful of frames so exposure/auto-focus settle.
        for _ in range(10):
            f = cam.read()
            if f is not None:
                frame = f
            time.sleep(0.05)
    finally:
        cam.release()
    return frame


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2

    name = argv[1]
    sources = argv[2:]
    face = _build_face()
    if not face.available():
        print("[enroll] FaceModule not available (insightface not installed or "
              "failed to load). Cannot enroll.")
        return 1

    total_ok = 0

    if sources == ["--camera"]:
        print("[enroll] Capturing one frame from the camera...")
        frame = _grab_camera_frame()
        if frame is None:
            print("[enroll] Could not capture a frame.")
            return 1
        ok, msg = face.enroll_from_image(name, frame)
        print(f"[enroll] {msg}")
        total_ok += 1 if ok else 0
    else:
        for path in sources:
            img = cv2.imread(path)
            if img is None:
                print(f"[enroll] Could not read image: {path}")
                continue
            ok, msg = face.enroll_from_image(name, img)
            print(f"[enroll] {path}: {msg}")
            total_ok += 1 if ok else 0

    print(f"[enroll] Done. {total_ok} image(s) enrolled for '{name}'. "
          f"Known embeddings now: {len(face.known_names)}.")
    return 0 if total_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
