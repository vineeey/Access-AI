"""DBSCAN clustering tests for auto-enrollment (Phase 9).

Repeated sightings of the SAME unknown face (near-identical 512-D embeddings)
should collapse into one dense cluster and, once past `suggest_after`, surface a
"save this visitor?" suggestion. A lone one-off sighting must stay noise
(unclustered). Uses a real SQLite store on a temp file.
"""

import datetime as dt

import numpy as np

from accessai.database import Database
from accessai.auto_enroll import AutoEnrollModule


def _normed(vec):
    v = np.asarray(vec, dtype=np.float32)
    n = float(np.linalg.norm(v))
    return v / n if n > 0 else v


def _base_vector(dim=512):
    return _normed(np.arange(1, dim + 1, dtype=np.float32))


def test_repeated_face_forms_a_suggestion(tmp_path):
    db = Database(str(tmp_path / "cluster.db"))
    auto = AutoEnrollModule(db, eps=0.35, min_samples=3, suggest_after=3)
    assert auto.available()

    now = dt.datetime.now().isoformat()
    base = _base_vector()

    # 4 near-identical sightings of one stranger -> one dense cluster.
    for i in range(4):
        auto.add_unknown_face(base, event_id=f"same-{i}", now_iso=now)

    # 1 orthogonal one-off -> should remain noise, not its own suggestion.
    noise = np.zeros(512, dtype=np.float32)
    noise[200] = 1.0
    auto.add_unknown_face(_normed(noise), event_id="oddball", now_iso=now)

    suggestions = auto.suggestions()
    assert len(suggestions) == 1
    # The cluster crosses suggest_after (3) at the 3rd sighting and is flagged
    # then; later members join the cluster but don't re-trigger a suggestion, so
    # the surfaced size reflects the members marked at suggest time (>= 3).
    assert suggestions[0]["size"] >= 3
    assert "same-0" in suggestions[0]["sample_event_ids"]


def test_below_min_samples_no_suggestion(tmp_path):
    db = Database(str(tmp_path / "cluster2.db"))
    auto = AutoEnrollModule(db, eps=0.35, min_samples=3, suggest_after=3)
    now = dt.datetime.now().isoformat()
    base = _base_vector()

    # Only 2 sightings -> below min_samples, no cluster.
    auto.add_unknown_face(base, event_id="a", now_iso=now)
    auto.add_unknown_face(base, event_id="b", now_iso=now)

    assert auto.suggestions() == []


def test_recompute_returns_empty_when_disabled_db_none():
    # No DB -> feature unavailable, degrades to empty (never raises).
    auto = AutoEnrollModule(db=None)
    assert auto.available() is False
    assert auto.recompute() == []
    assert auto.suggestions() == []
