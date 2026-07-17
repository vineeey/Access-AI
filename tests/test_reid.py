"""Cosine-match tests for the Re-ID gallery (Phase 9).

We drive ReidModule.identify() directly with hand-built L2-normalised vectors
(no camera / cv2 needed) against a real SQLite gallery on a temp file. This pins
the "same stranger -> reuse id + bump count, different stranger -> new id"
behaviour that powers the "same visitor came N times today" announcement.
"""

import datetime as dt

import numpy as np

from accessai.database import Database
from accessai.reid_module import ReidModule


def _unit(*, dim=16, hot=0):
    """A one-hot (already L2-normalised) float32 vector."""
    v = np.zeros(dim, dtype=np.float32)
    v[hot] = 1.0
    return v


def _module(tmp_path):
    db = Database(str(tmp_path / "reid.db"))
    # Force the histogram (placeholder) backend; identify() itself is backend-free.
    return ReidModule(backend="histogram", db=db, match_threshold=0.75)


def test_first_sighting_mints_new_id(tmp_path):
    reid = _module(tmp_path)
    now = dt.datetime.now().isoformat()
    rid, count = reid.identify(_unit(hot=0), now)
    assert rid is not None and rid.startswith("v_")
    assert count == 1


def test_same_appearance_reuses_id_and_bumps_count(tmp_path):
    reid = _module(tmp_path)
    now = dt.datetime.now().isoformat()
    emb = _unit(hot=0)
    rid1, c1 = reid.identify(emb, now)
    rid2, c2 = reid.identify(emb, now)          # identical -> cosine 1.0
    assert rid2 == rid1
    assert c1 == 1 and c2 == 2


def test_different_appearance_gets_new_id(tmp_path):
    reid = _module(tmp_path)
    now = dt.datetime.now().isoformat()
    rid1, _ = reid.identify(_unit(hot=0), now)
    rid2, c2 = reid.identify(_unit(hot=1), now)  # orthogonal -> cosine 0.0
    assert rid2 != rid1
    assert c2 == 1


def test_none_embedding_is_safe(tmp_path):
    reid = _module(tmp_path)
    assert reid.identify(None, dt.datetime.now().isoformat()) == (None, 0)
