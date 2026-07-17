# PHASE 3 PROMPT — Object & Scene Detection (YOLOv8) + Context/Intent Engine

Paste EVERYTHING inside the fenced block below as your next message to the Claude
agent in VS Code (the `AccessAI` workspace with Phases 1 & 2 complete).

---

```
You are continuing the AccessAI project. Phases 1 (Foundation) and 2 (Face
Recognition, InsightFace) are COMPLETE and verified. Build ONLY Phase 3 now:
OBJECT & SCENE DETECTION with YOLOv8, plus a CONTEXT/INTENT ENGINE that fuses
face + objects into a conservative "likely intent". Do not build later phases.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (match exact interfaces)
====================================================================
Read fully before changing anything:
- config.py                  (flags incl. ENABLE_VISION; add a Vision section)
- accessai/visitor_event.py  (VisitorEvent + DetectedObject already exist:
                              detected_objects, carried_objects, visitor_count,
                              intent, confidence, announcement_text)
- accessai/pipeline.py       (run_once already sets identity from Phase 2 and an
                              interim announcement; Pipeline.__init__ already
                              accepts vision=, vision_enabled=)
- accessai/face_module.py    (the module pattern to mirror: guarded import,
                              available(), logging)
- run.py                     (where modules are instantiated + injected)
- accessai/server.py, web/*  (UI to extend)

Do NOT restructure. Phase 3 FILLS existing fields (detected_objects,
carried_objects, visitor_count, intent, confidence), adds ONE new module + ONE
pure-function engine, flips ENABLE_VISION, and enriches the announcement +　UI.
Restate understanding in 3-4 bullets before coding.

====================================================================
GOAL
====================================================================
On "Ring", after face recognition, run YOLOv8 on the same frame to detect people
and carried objects (bags/parcels). Reconcile visitor_count. Then a context
engine decides a conservative intent (known visitor / likely delivery / unknown
visitor / no visitor detected) from all available signals. CPU-only, Python 3.12.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) requirements.txt ---
Uncomment/add exactly:
  ultralytics==8.2.103
Leave other later-phase deps commented. Note in a comment that ultralytics pulls
in torch (CPU build) and that yolov8n.pt (~6 MB) auto-downloads on first use.

--- 2) config.py — add a Vision / Object detection section ---
  YOLO_MODEL = "yolov8n.pt"     # nano = fast, CPU-friendly; auto-downloads once
  YOLO_CONF = 0.4               # detection confidence threshold
  # COCO has NO native "parcel/box" class. These are the carried items we treat
  # as delivery-ish; Phase 6 OCR refines "is this actually a courier parcel".
  PARCEL_LABELS = {"backpack", "handbag", "suitcase", "book"}
Keep ENABLE_VISION; set it True at the end of this phase.
Add a comment: "book" is included because small boxes are frequently detected as
book/handbag by COCO models; wording stays conservative ("a package").

--- 3) accessai/vision_module.py  (NEW) ---
Mirror the FaceModule robustness pattern (guarded import, available(), logging).

Guarded import:
    from ultralytics import YOLO

class VisionModule:
  __init__(self, model_path="yolov8n.pt", conf=0.4):
     - Store conf. If ultralytics imported OK: print a loading line, self.model =
       YOLO(model_path); self.class_names = dict(self.model.names). Wrap in
       try/except; on failure set self.model=None and log (never raise).
  available(self) -> bool: ultralytics imported AND self.model is not None.
  detect(self, frame_bgr) -> list[dict]:
     - If not available(): return [].
     - results = self.model.predict(frame_bgr, conf=self.conf, verbose=False)
     - If empty or results[0].boxes is None/empty: return [].
     - For each box: read xyxy (ints), conf (float), cls id (int) -> label via
       self.class_names. Return [{"label","confidence","box":(x1,y1,x2,y2)}].
  @staticmethod
  summarize(detections, parcel_labels) -> tuple[list[str], int]:
     - person_count = count of detections with label == "person".
     - carried = pretty names for detections whose label is in parcel_labels,
       using a mapping: backpack->"a backpack", handbag->"a handbag",
       suitcase->"a suitcase", book->"a package". De-duplicate while preserving
       order (e.g. two backpacks -> report once as "a backpack", or "two
       backpacks" if you want; keep it simple and conservative — a set is fine).
     - return (carried, person_count).

--- 4) accessai/context_engine.py  (NEW, pure functions — NOT injected) ---
This centralises intent so later phases (spoof/ocr/reid) just add signals here.
It has NO heavy deps, so pipeline imports it directly (no constructor injection).

  def infer_intent(ev) -> tuple[str, float]:
     Inputs it reads from the VisitorEvent: ev.is_spoof, ev.identity.known,
     ev.carried_objects, ev.ocr_text (empty until Phase 6), ev.visitor_count,
     ev.detected_objects, ev.reid_seen_count (0 until Phase 9).
     Rules (conservative, in priority order):
       1. if ev.is_spoof: return ("possible spoof attempt", 0.6)   # false for now
       2. if ev.identity.known: return ("known visitor", 0.9)
       3. parcel_like = any carried object looks like a parcel/bag/suitcase/
          backpack/package (check ev.carried_objects strings).
          courier_hit = any known courier keyword appears in ev.ocr_text.lower()
          (ocr_text is "" until Phase 6, so this is future-proof, not active now).
          - if parcel_like and courier_hit: ("likely delivery", 0.85)
          - if parcel_like:                 ("likely delivery", 0.65)
       4. if ev.visitor_count == 0 and not ev.detected_objects:
             ("no visitor detected", 0.3)
       5. else: ("unknown visitor", 0.5)
     Never output "definitely" anywhere.

  def compose_interim_announcement(ev) -> str:
     Build a short, conservative sentence from the event. Phase 4 will REPLACE
     this with a full accessibility engine, so keep it simple but correct:
       - who: known -> "<Name> is at the door." ;
              spoof -> "Warning: a face was shown but it looks like a photo." ;
              visitor_count>0 -> "An unknown visitor is at the door." ;
              else -> "The doorbell rang but no one is clearly visible."
       - if carried_objects: append " Carrying " + join(carried) + "."
       - if intent == "likely delivery": append " Likely a delivery."
     Return the joined string.

--- 5) accessai/pipeline.py — wire vision + context engine into run_once ---
Import: from .context_engine import infer_intent, compose_interim_announcement
(keep the Identity import from Phase 2).

After the Phase-2 face block (which sets ev.identity, ev.face_box, and a face-
based visitor_count), INSERT the vision step and REPLACE the interim announcement
logic with the context engine:

  # --- Object detection (Phase 3) ---
  face_count = ev.visitor_count  # from Phase 2 (# of faces)
  if self.vision_enabled and self.vision is not None and self.vision.available():
      detections = self.vision.detect(frame_bgr)
      ev.detected_objects = [
          DetectedObject(label=d["label"], confidence=d["confidence"],
                         box=tuple(d["box"])) for d in detections
      ]
      carried, person_count = self.vision.summarize(detections,
                                                    self._parcel_labels)
      ev.carried_objects = carried
      # Reconcile: trust the larger of (faces seen, people detected)
      ev.visitor_count = max(face_count, person_count)

  # --- Intent + interim announcement (Phase 3) ---
  ev.intent, ev.confidence = infer_intent(ev)
  ev.announcement_text = compose_interim_announcement(ev)

Import DetectedObject from .visitor_event at the top. Add self._parcel_labels in
__init__ (accept a parcel_labels kwarg defaulting to a small built-in set, and
pass config.PARCEL_LABELS from run.py). Do NOT remove the Phase-2 face logic; the
context engine simply overrides the interim intent/announcement that Phase 2 set
inline. Keep snapshot + db.save_event + return unchanged. Leave later-phase TODOs.

--- 6) run.py — instantiate + inject VisionModule and parcel labels ---
Import VisionModule. Build:
  vision = None
  if config.ENABLE_VISION:
      vision = VisionModule(model_path=config.YOLO_MODEL, conf=config.YOLO_CONF)
Pass into Pipeline (keep the Phase-2 face args):
  pipeline = Pipeline(db=db, history_dir=config.HISTORY_DIR,
                      face=face, face_enabled=config.ENABLE_FACE,
                      vision=vision, vision_enabled=config.ENABLE_VISION,
                      parcel_labels=config.PARCEL_LABELS)
If Pipeline.__init__ doesn't yet accept parcel_labels, add it (default to a small
built-in set) without breaking existing call sites.

--- 7) web UI — show objects + intent ---
- Current Visitor card: add an "intent" chip and a "carrying" line listing
  ev.carried_objects. Show a small list of detected object labels
  (label + confidence) if present.
- History list items: append the intent chip.
- OPTIONAL (only if quick and clean): draw bounding boxes on the snapshot for the
  event detail — skip if it risks breaking the existing image serving. The card
  text is what matters.
- Keep vanilla JS, no CDN.

--- 8) Flip the flag ---
Set ENABLE_VISION = True in config.py.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Install: source .venv/bin/activate && pip install -r requirements.txt
   (first predict() downloads yolov8n.pt ~6MB).
2. Syntax: python -m py_compile on every .py; fix all errors.
3. Start: python3 run.py — confirm VisionModule loads and the server starts.
   The app MUST still start if ultralytics failed to import (graceful) and if
   ENABLE_VISION were False.
4. Ring with different scenes and paste the event JSONs:
   a) A known face, no object -> intent "known visitor", carried_objects [].
   b) An unknown face holding a bag/backpack/box -> detected_objects includes the
      item, carried_objects non-empty, intent "likely delivery",
      announcement mentions "Carrying ... Likely a delivery."
   c) Empty/blank frame -> "no visitor detected".
   (If you cannot pose live, reuse archived snapshots or any test image containing
    a person and/or a bag, and SAY which image you used — be honest about method,
    like you were in Phase 2.)
5. Confirm visitor_count reconciliation: a frame with 2 people -> visitor_count 2.
6. Confirm Phases 1 & 2 did not regress: /video, /trigger, /history, /snapshot,
   /mode, /enroll, /known all still behave; face recognition still names a known
   person; conservative language preserved (no "definitely").

====================================================================
GUARDRAILS
====================================================================
- Do not open a camera outside accessai/camera.py.
- Do not rename/remove VisitorEvent fields or Database methods.
- Context engine stays pure (no I/O, no model loading) so later phases can unit-
  test it and add signals cheaply.
- Keep the app runnable with ENABLE_VISION or ENABLE_FACE flipped off.
- CPU-only. Match existing code style (guarded imports, available(), WHY-docstrings).

FIRST restate understanding + list files to create/modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## After Phase 3, send me a report with:
1. Startup log showing VisionModule loaded (+ yolov8n.pt download note).
2. Three `/trigger` event JSONs: known-no-object, unknown-with-parcel, empty —
   showing `detected_objects`, `carried_objects`, `intent`, `announcement_text`.
3. The 2-people `visitor_count` reconciliation result.
4. Which test images/scenes you used (be honest about method).
5. Any errors + fixes; confirmation Phases 1–2 didn't regress.

Then I'll give you the **Phase 4 prompt** (Accessibility Output — TTS + Blind/Deaf
modes + two-way reply), which finally makes it *speak*.
