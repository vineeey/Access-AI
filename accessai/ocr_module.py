"""
OCRModule - parcel / label text reading (Phase 6).

A THIN wrapper around VLMModule. The combined VLM call already returns both the
scene sentence AND any visible label text in ONE request, so in the live
pipeline we read OCR straight off vlm.describe_and_read() to avoid a second
rate-limited API round-trip.

This module exists so that:
  * OCR has its own injected slot + ENABLE_OCR flag (the VisitorEvent-spine
    pattern: one module per capability), and
  * OCR can later be swapped for a dedicated local engine (e.g. PaddleOCR on the
    high-end build) behind this exact interface - available() + read_labels() -
    without the pipeline knowing or caring.

Fail-soft like every module: if no VLM is wired, available() is False and
read_labels() returns "".
"""


class OCRModule:
    def __init__(self, vlm=None):
        self.vlm = vlm

    def available(self) -> bool:
        return self.vlm is not None and self.vlm.available()

    def read_labels(self, frame_bgr) -> str:
        """Standalone OCR (used if ever called directly). The live pipeline
        instead reuses the scene+labels combined call for efficiency."""
        if not self.available():
            return ""
        return self.vlm.read_labels(frame_bgr)
