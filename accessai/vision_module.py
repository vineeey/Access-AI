"""
VisionModule - object & scene detection with YOLOv8 (Phase 3).

Mirrors the robustness pattern of FaceModule:
  - the heavy dependency (ultralytics) is imported behind a guard,
  - the constructor NEVER raises (a load failure just leaves the module
    unavailable), and
  - available() lets the pipeline skip this step cleanly.

On "Ring", the pipeline calls detect() on the same frame the face module saw.
detect() returns raw detections; summarize() turns them into a person count and
a short, conservative list of carried objects (bags/parcels) for the announcement.

CPU-only, Python 3.12. The nano model (yolov8n.pt, ~6 MB) auto-downloads once on
the first predict() call.
"""

# --- Guarded heavy import (never crash if ultralytics/torch is missing) ------
try:
    from ultralytics import YOLO
    _HAS_YOLO = True
except Exception as e:                                   # pragma: no cover
    _HAS_YOLO = False
    print(f"[VisionModule] ultralytics not available, object detection disabled: {e}")


# COCO label -> conservative human-readable phrase for the announcement.
# We deliberately say "a package" for COCO's "book": small courier boxes are very
# often detected as book/handbag by a nano COCO model. Phase 6 (OCR) refines
# whether it is actually a courier parcel; until then wording stays cautious.
_CARRIED_PRETTY = {
    "backpack": "a backpack",
    "handbag": "a handbag",
    "suitcase": "a suitcase",
    "book": "a package",
}


class VisionModule:
    def __init__(self, model_path: str = "yolov8n.pt", conf: float = 0.4,
                 extra_person_conf: float = 0.6):
        self.conf = conf
        # Stricter bar for counting an EXTRA (faceless) person than for merely
        # detecting objects: a phantom second visitor is announced to the user,
        # so precision matters more than recall here. Never below `conf`.
        self.extra_person_conf = max(float(extra_person_conf), float(conf))
        self.model = None
        self.class_names: dict = {}
        if not _HAS_YOLO:
            return
        try:
            print(f"[VisionModule] Loading YOLOv8 '{model_path}' on CPU "
                  f"(first run auto-downloads ~6 MB)...")
            self.model = YOLO(model_path)
            # Copy the id->name map once so detect() never touches model internals.
            self.class_names = dict(self.model.names)
            print(f"[VisionModule] Loaded. {len(self.class_names)} COCO classes, "
                  f"conf>={self.conf}.")
        except Exception as e:                            # pragma: no cover
            self.model = None
            print(f"[VisionModule] Failed to load YOLO model: {e}")

    # ------------------------------------------------------------------
    def available(self) -> bool:
        return _HAS_YOLO and self.model is not None

    # ------------------------------------------------------------------
    def detect(self, frame_bgr) -> list[dict]:
        """Detect objects in one BGR frame.

        Returns a list of {"label", "confidence", "box": (x1,y1,x2,y2)}.
        Returns [] on any problem so the pipeline degrades gracefully.
        """
        if not self.available() or frame_bgr is None:
            return []
        try:
            results = self.model.predict(frame_bgr, conf=self.conf, verbose=False)
        except Exception as e:                            # pragma: no cover
            print(f"[VisionModule] predict() failed: {e}")
            return []
        if not results:
            return []

        boxes = results[0].boxes
        if boxes is None or len(boxes) == 0:
            return []

        out: list[dict] = []
        for b in boxes:
            try:
                x1, y1, x2, y2 = (int(v) for v in b.xyxy[0].tolist())
                confidence = float(b.conf[0].item())
                cls_id = int(b.cls[0].item())
            except Exception:                             # pragma: no cover
                continue
            label = self.class_names.get(cls_id, str(cls_id))
            out.append({
                "label": label,
                "confidence": round(confidence, 3),
                "box": (x1, y1, x2, y2),
            })
        return out

    # ------------------------------------------------------------------
    @staticmethod
    def summarize(detections: list[dict], parcel_labels) -> tuple[list[str], int]:
        """Reduce raw detections to (carried_objects, person_count).

        - person_count: number of "person" detections (used to reconcile the
          face-based visitor_count in the pipeline).
        - carried_objects: de-duplicated, conservative phrases for any detection
          whose label is in `parcel_labels` (order preserved, no repeats).
        """
        person_count = 0
        carried: list[str] = []
        seen: set[str] = set()
        for d in detections:
            label = d.get("label", "")
            if label == "person":
                person_count += 1
            elif label in parcel_labels:
                phrase = _CARRIED_PRETTY.get(label, f"a {label}")
                if phrase not in seen:
                    seen.add(phrase)
                    carried.append(phrase)
        return carried, person_count

    # ------------------------------------------------------------------
    @staticmethod
    def _iou(a, b) -> float:
        """Intersection-over-union of two (x1,y1,x2,y2) boxes."""
        ix1, iy1 = max(a[0], b[0]), max(a[1], b[1])
        ix2, iy2 = min(a[2], b[2]), min(a[3], b[3])
        iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
        inter = iw * ih
        if inter <= 0:
            return 0.0
        area_a = max(0, a[2] - a[0]) * max(0, a[3] - a[1])
        area_b = max(0, b[2] - b[0]) * max(0, b[3] - b[1])
        union = area_a + area_b - inter
        return inter / union if union > 0 else 0.0

    @staticmethod
    def _contains_face(person_box, face_box) -> bool:
        """True if the face's centre lies inside the person box — a body box
        normally contains its own face, so this ties a YOLO person to an already
        recognised face instead of double-counting it as an extra visitor."""
        fx = (face_box[0] + face_box[2]) / 2.0
        fy = (face_box[1] + face_box[3]) / 2.0
        return person_box[0] <= fx <= person_box[2] and person_box[1] <= fy <= person_box[3]

    def count_extra_people(self, detections: list[dict], face_boxes,
                           iou_thresh: float = 0.55) -> int:
        """Count YOLO 'person' boxes that are genuinely EXTRA visitors — a body
        with no recognised face (turned away / partially visible).

        Guards against the two ways a nano COCO model inflates the head-count:
          - weak false positives (a pillow, a phone, a reflection) -> confidence
            gate at self.extra_person_conf, stricter than the detection threshold;
          - duplicate / overlapping boxes for ONE body, and body boxes that simply
            wrap an already-recognised face -> IoU de-dup + face-containment check.

        `face_boxes` are the boxes of faces already turned into Person records.
        Returns the number of unaccounted-for people (0 when everyone has a face).
        """
        persons = sorted(
            (d for d in detections
             if d.get("label") == "person"
             and float(d.get("confidence", 0.0)) >= self.extra_person_conf),
            key=lambda d: float(d.get("confidence", 0.0)), reverse=True,
        )
        faces = [tuple(b) for b in (face_boxes or []) if tuple(b) != (0, 0, 0, 0)]
        kept: list[tuple] = []
        extra = 0
        for d in persons:
            box = tuple(d["box"])
            # Skip a second detection of a body already counted.
            if any(self._iou(box, k) >= iou_thresh for k in kept):
                continue
            kept.append(box)
            # A body wrapping a recognised face is that same person, not a new one.
            if any(self._contains_face(box, f) for f in faces):
                continue
            extra += 1
        return extra
