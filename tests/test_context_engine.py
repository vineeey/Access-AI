"""PURE-logic tests for the context / intent engine (Phase 3).

infer_intent() fuses signals already written onto a VisitorEvent and returns a
conservative (intent, confidence). These tests pin every branch and its
confidence so a future edit can't silently change the doorbell's behaviour.
"""

from accessai.context_engine import (
    infer_intent,
    _looks_like_parcel,
    _has_courier_text,
)
from accessai.visitor_event import VisitorEvent, Identity, DetectedObject


def _ev(**kw) -> VisitorEvent:
    """A blank event with an id + timestamp; override any field via kwargs."""
    ev = VisitorEvent(event_id="e1", timestamp="2026-07-10T12:00:00")
    for k, v in kw.items():
        setattr(ev, k, v)
    return ev


def test_spoof_wins_over_everything():
    # Even a KNOWN face is overridden by a spoof flag (safety first).
    ev = _ev(is_spoof=True, identity=Identity(known=True, name="Alice"))
    assert infer_intent(ev) == ("possible spoof attempt", 0.6)


def test_known_face():
    ev = _ev(identity=Identity(known=True, name="Alice", confidence=0.9))
    assert infer_intent(ev) == ("known visitor", 0.9)


def test_parcel_plus_courier_text():
    ev = _ev(carried_objects=["a package"], ocr_text="FedEx Express")
    assert infer_intent(ev) == ("likely delivery", 0.85)


def test_parcel_only_without_courier_text():
    ev = _ev(carried_objects=["a backpack"], visitor_count=1)
    assert infer_intent(ev) == ("likely delivery", 0.65)


def test_no_visitor_no_objects():
    ev = _ev(visitor_count=0, detected_objects=[])
    assert infer_intent(ev) == ("no visitor detected", 0.3)


def test_unknown_visitor_fallback():
    ev = _ev(visitor_count=1,
             detected_objects=[DetectedObject(label="person", confidence=0.8)])
    assert infer_intent(ev) == ("unknown visitor", 0.5)


def test_custom_courier_keyword_injection():
    # The pipeline injects config.COURIER_KEYWORDS; a bespoke keyword should count.
    ev = _ev(carried_objects=["a box"], ocr_text="ACME LOGISTICS")
    assert infer_intent(ev, courier_keywords=("acme logistics",)) \
        == ("likely delivery", 0.85)


def test_parcel_hint_helpers():
    assert _looks_like_parcel(["a suitcase"]) is True
    assert _looks_like_parcel(["an umbrella"]) is False
    assert _looks_like_parcel([]) is False
    assert _has_courier_text("shipped via DHL") is True
    assert _has_courier_text("") is False
