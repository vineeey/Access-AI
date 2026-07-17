"""
Context / Intent engine (Phase 3) - PURE functions, no heavy dependencies.

This is where AccessAI decides "what is likely going on at the door" by FUSING
signals that other modules have already written onto the VisitorEvent:

    face (Phase 2) + objects (Phase 3) + spoof (Phase 5) + OCR (Phase 6) +
    re-ID (Phase 9)

Because it has NO model loading and NO I/O, the pipeline imports these functions
directly (they are not injected like the AI modules). Later phases add signals by
reading MORE fields here - never by restructuring the pipeline. Keeping it pure
also means it can be unit-tested in isolation.

Guiding rule for every phase: language stays CONSERVATIVE. We say "likely" and
"looks like"; we never say "definitely".
"""


# Courier keywords used ONLY once OCR is live (Phase 6). ocr_text is "" until
# then, so this list is future-proofing - it does not change behaviour today.
_COURIER_KEYWORDS = (
    "fedex", "dhl", "ups", "amazon", "usps", "bluedart", "delhivery",
    "dtdc", "ekart", "shiprocket", "courier", "parcel", "package", "delivery",
)

# Substrings that mark a carried object as parcel-like. carried_objects holds
# human-readable phrases (e.g. "a backpack", "a package"), so we match on those.
_PARCEL_HINTS = ("parcel", "package", "backpack", "bag", "suitcase", "box")


def _looks_like_parcel(carried_objects) -> bool:
    """True if any carried phrase looks like a bag/parcel/package."""
    for phrase in carried_objects or []:
        low = phrase.lower()
        if any(hint in low for hint in _PARCEL_HINTS):
            return True
    return False


def _has_courier_text(ocr_text, courier_keywords=_COURIER_KEYWORDS) -> bool:
    """True if OCR text contains a known courier keyword (active from Phase 6)."""
    low = (ocr_text or "").lower()
    return any(kw in low for kw in (courier_keywords or _COURIER_KEYWORDS))


def infer_intent(ev, courier_keywords=_COURIER_KEYWORDS) -> tuple[str, float]:
    """Decide a conservative (intent, confidence) from all available signals.

    `courier_keywords` is injected by the pipeline (from config.COURIER_KEYWORDS)
    so this module stays PURE - no config import. It defaults to the built-in
    list so the function is still usable / testable standalone.

    Priority order (first match wins):
      1. spoof            -> "possible spoof attempt"   (0.6)
      2. known face       -> "known visitor"            (0.9)
      3. parcel + courier -> "likely delivery"          (0.85)  [courier text from OCR, Phase 6]
         parcel only      -> "likely delivery"          (0.65)
      4. nobody, nothing  -> "no visitor detected"      (0.3)
      5. otherwise        -> "unknown visitor"          (0.5)
    """
    if getattr(ev, "is_spoof", False):
        return ("possible spoof attempt", 0.6)

    if ev.identity.known:
        return ("known visitor", 0.9)

    parcel_like = _looks_like_parcel(ev.carried_objects)
    courier_hit = _has_courier_text(ev.ocr_text, courier_keywords)
    if parcel_like and courier_hit:
        return ("likely delivery", 0.85)
    if parcel_like:
        return ("likely delivery", 0.65)

    if ev.visitor_count == 0 and not ev.detected_objects:
        return ("no visitor detected", 0.3)

    return ("unknown visitor", 0.5)


def compose_interim_announcement(ev) -> str:
    """Build a short, conservative sentence from the event.

    Phase 4 REPLACES this with a full accessibility engine (per-mode phrasing,
    TTS). Until then this keeps the announcement correct and cautious. Reads
    ev.intent, so call infer_intent() first.
    """
    if getattr(ev, "is_spoof", False):
        who = "Warning: a face was shown but it looks like a photo."
    elif ev.identity.known:
        who = f"{ev.identity.name} is at the door."
    elif ev.visitor_count > 0:
        who = "An unknown visitor is at the door."
    else:
        who = "The doorbell rang but no one is clearly visible."

    parts = [who]
    if ev.carried_objects:
        parts.append(f"Carrying {', '.join(ev.carried_objects)}.")
    if ev.intent == "likely delivery":
        parts.append("Likely a delivery.")
    return " ".join(parts)
