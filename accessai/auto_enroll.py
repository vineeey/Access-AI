"""
Auto-Enrollment module (Phase 9) - notice a face we keep seeing, and offer to
save it, so the user never has to manually register a photo.

HOW
---
Every UNKNOWN face's 512-D ArcFace embedding (from the Phase-2 FaceModule) is
stashed. Periodically we run DBSCAN over those embeddings on COSINE distance:
same person's sightings land in one dense cluster; one-off strangers stay as
noise. When a cluster grows to `suggest_after` sightings, we surface a
"Save this visitor?" prompt. Confirming promotes a representative embedding into
the FaceModule's gallery, so the visitor is recognised by NAME from then on.

WHY DBSCAN (not k-means): we don't know how many distinct strangers exist, and
we want to leave rare one-offs UNclustered (noise) rather than force them into a
group. DBSCAN needs neither a cluster count nor centroids and treats sparse
points as noise - exactly the behaviour we want.

Cost control: DBSCAN is O(n^2), so it does NOT run on every trigger. It runs
periodically (every few adds) and lazily when the UI asks for suggestions.

Degrades gracefully: no scikit-learn => available() is False and the whole
feature is skipped; the event proceeds exactly as Phase 8. Never raises.
"""

from collections import defaultdict

import numpy as np

try:
    from sklearn.cluster import DBSCAN
    _HAS_SK = True
    _IMPORT_ERR = None
except Exception as e:                                    # pragma: no cover
    _HAS_SK = False
    _IMPORT_ERR = e
    print(f"[AutoEnrollModule] scikit-learn not available: {e}\n"
          "             Auto-enrollment disabled (app still runs). "
          "Install with: pip install scikit-learn==1.5.2")


class AutoEnrollModule:
    def __init__(self, db, eps=0.35, min_samples=3, suggest_after=5, face=None):
        self.db = db
        self.eps = float(eps)
        self.min_samples = int(min_samples)
        self.suggest_after = int(suggest_after)
        self.face = face                    # for confirm() -> known enrollment
        # Recompute cadence: after this many new faces, re-cluster. Kept small so
        # a suggestion appears promptly, but never per-trigger.
        self._recompute_every = max(1, self.min_samples)
        self._adds_since = 0
        print(f"[AutoEnrollModule] eps={self.eps} min_samples={self.min_samples} "
              f"suggest_after={self.suggest_after} | "
              f"{'ready' if _HAS_SK else 'disabled (no sklearn)'}")

    # ------------------------------------------------------------------
    def available(self) -> bool:
        return _HAS_SK and self.db is not None

    def set_face(self, face) -> None:
        """Let run.py wire the FaceModule after construction (for confirm())."""
        self.face = face

    # ------------------------------------------------------------------
    def add_unknown_face(self, embedding, event_id, now_iso) -> None:
        """Stash one unknown-face embedding; re-cluster every few adds."""
        if not self.available() or embedding is None:
            return
        try:
            emb = np.asarray(embedding, dtype=np.float32)
            self.db.cluster_add(emb.tobytes(), event_id, now_iso)
        except Exception as e:                            # pragma: no cover
            print(f"[AutoEnrollModule] add failed: {e}")
            return
        self._adds_since += 1
        if self._adds_since >= self._recompute_every:
            self._adds_since = 0
            try:
                self.recompute()
            except Exception as e:                        # pragma: no cover
                print(f"[AutoEnrollModule] recompute failed: {e}")

    # ------------------------------------------------------------------
    def recompute(self) -> list:
        """Cluster the open unknown faces; return any NEWLY-suggested clusters.

        Cluster ids are STABLE across runs: a cluster is named after its
        earliest-inserted member row (membership only grows, so that anchor never
        changes). New suggestions are those crossing `suggest_after` for the first
        time (their members flip suggested 0 -> 1).
        """
        if not self.available():
            return []
        rows = self.db.cluster_rows(include_resolved=False)
        if len(rows) < self.min_samples:
            return []

        vecs = [np.frombuffer(r["embedding"], dtype=np.float32) for r in rows]
        dim = len(vecs[0])
        keep = [(r, v) for r, v in zip(rows, vecs) if len(v) == dim]
        if len(keep) < self.min_samples:
            return []
        rows = [r for r, _ in keep]
        X = np.vstack([v for _, v in keep]).astype(np.float32)

        labels = DBSCAN(eps=self.eps, min_samples=self.min_samples,
                        metric="cosine").fit_predict(X)

        groups = defaultdict(list)
        for row, lab in zip(rows, labels):
            if lab == -1:                                 # noise = leave unclustered
                continue
            groups[int(lab)].append(row)

        new_suggestions = []
        for members in groups.values():
            members = sorted(members, key=lambda r: r["id"])
            cid = "c_" + str(members[0]["id"])
            row_ids = [r["id"] for r in members]
            # Persist the (stable) cluster id on every member.
            self.db.cluster_update(row_ids, cluster_id=cid)
            already_suggested = any(r["suggested"] == 1 for r in members)
            if len(members) >= self.suggest_after and not already_suggested:
                self.db.cluster_update(row_ids, suggested=1)
                new_suggestions.append({
                    "cluster_id": cid,
                    "size": len(members),
                    "sample_event_ids": [r["event_id"] for r in members[:3]],
                    "sample_event_id": members[0]["event_id"],
                })
        return new_suggestions

    # ------------------------------------------------------------------
    def suggestions(self) -> list:
        """Currently-open 'save this visitor?' prompts (re-clusters lazily first)."""
        if not self.available():
            return []
        try:
            self.recompute()
        except Exception as e:                            # pragma: no cover
            print(f"[AutoEnrollModule] recompute failed: {e}")
        groups = defaultdict(list)
        for r in self.db.cluster_rows(include_resolved=False):
            if r["suggested"] == 1 and r["cluster_id"]:
                groups[r["cluster_id"]].append(r)
        out = []
        for cid, members in groups.items():
            members = sorted(members, key=lambda r: r["id"])
            out.append({
                "cluster_id": cid,
                "size": len(members),
                "sample_event_id": members[0]["event_id"],
                "sample_event_ids": [r["event_id"] for r in members[:3]],
            })
        return out

    # ------------------------------------------------------------------
    def _members(self, cluster_id) -> list:
        return [r for r in self.db.cluster_rows(include_resolved=False)
                if r["cluster_id"] == cluster_id]

    def confirm(self, cluster_id, name) -> bool:
        """Promote a cluster to a KNOWN face and resolve the suggestion."""
        if not self.available():
            return False
        name = (name or "").strip()
        if not name:
            return False
        members = self._members(cluster_id)
        if not members:
            return False
        # Representative = mean of the cluster's embeddings, renormalised. Averaging
        # several sightings is more stable than picking one frame.
        embs = [np.frombuffer(r["embedding"], dtype=np.float32) for r in members]
        rep = np.mean(np.vstack(embs), axis=0).astype(np.float32)
        norm = float(np.linalg.norm(rep))
        if norm > 0:
            rep = rep / norm

        ok = True
        if self.face is not None and self.face.available():
            ok = self.face.enroll_embedding(name, rep)
        self.db.cluster_update([r["id"] for r in members], suggested=2)
        return bool(ok)

    def dismiss(self, cluster_id) -> bool:
        """Resolve a suggestion WITHOUT enrolling (user isn't interested)."""
        if not self.available():
            return False
        members = self._members(cluster_id)
        if not members:
            return False
        self.db.cluster_update([r["id"] for r in members], suggested=2)
        return True
