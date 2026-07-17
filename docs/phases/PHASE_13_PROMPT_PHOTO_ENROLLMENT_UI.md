# PHASE 13 PROMPT — Upload-Photo Enrollment UI (register known people by photo + name)

A focused add-on: a dashboard panel to UPLOAD one or more photos of a person, give
them a NAME, extract + save their face embedding, and manage the known-people list
(view / delete). Paste EVERYTHING in the fenced block below as your next message to
the Claude agent in VS Code.

---

```
You are enhancing the completed AccessAI project (Phases 1–12 done, working). Build
ONLY this feature: a proper UPLOAD-PHOTO ENROLLMENT flow in the dashboard, so a
user can register known people from image files (not just the live camera), with
names, and manage them. Do NOT change unrelated behaviour.

====================================================================
GOAL
====================================================================
From the dashboard, the user can:
  1. Type a person's NAME and UPLOAD one or more PHOTOS of them.
  2. The system detects the face in each photo, extracts the InsightFace embedding,
     saves it, and adds it to the recognition gallery IMMEDIATELY (no restart).
  3. See a "Known People" list (name + how many photos) and DELETE a person.
Thereafter, when that person appears at the door, they are recognised by name —
exactly like the existing live-view enrollment, but from uploaded photos.

Multiple photos per person are ENCOURAGED (different angles/lighting) — each photo
becomes another embedding under the same name, which improves match reliability.

====================================================================
TORCH SAFETY
====================================================================
No new pip install is needed (this reuses the existing InsightFace FaceModule and
FastAPI file uploads via python-multipart, already installed). If you think you
need a new dependency, you don't. If you install anything, verify torch is still
2.4.1 and YOLO bus.jpg still detects.

====================================================================
STEP 0 — READ CURRENT CODE FIRST
====================================================================
Read fully before changing:
- accessai/face_module.py   (FaceModule: load_known(), identify(),
                             enroll_from_image(name, image_bgr) -> (ok, msg),
                             known_names / known_embeddings in-memory gallery,
                             embed_largest_face(); known_dir = data/known_faces)
- accessai/database.py      (known_faces table: name, source_path, embedding,
                             created_at — persist embeddings here too if the
                             existing code does; add delete/query helpers)
- accessai/server.py        (existing POST /enroll (live view), GET /known;
                             add upload + delete routes here)
- config.py                 (KNOWN_FACES_DIR)
- web/index.html, app.js, style.css (existing Enroll panel — extend it)
Restate understanding in 3-4 bullets before coding. REUSE
FaceModule.enroll_from_image — do NOT reimplement embedding logic.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) FaceModule — make sure it supports file-based enrollment cleanly ---
FaceModule already has enroll_from_image(name, image_bgr). Add/confirm:
  enroll_from_files(self, name, list_of_image_bgr) -> dict:
     - For each image: detect faces; if none -> record "no face" for that file; if
       multiple -> use the LARGEST and note a warning; else use it.
     - Save each accepted image to KNOWN_FACES_DIR/<name>/<timestamp_idx>.jpg.
     - Append the embedding + name to the in-memory gallery so recognition works
       immediately WITHOUT restart.
     - Also persist the embedding to the known_faces DB table (in try/except; a DB
       hiccup must not block enrollment).
     - Return {"name":name, "added":N, "skipped":[reasons], "known_count":total,
               "photos_for_name":count}.
  remove_person(self, name) -> dict:
     - Delete KNOWN_FACES_DIR/<name>/ (and any direct <name>.jpg), remove all
       in-memory embeddings/names for that person, and delete their rows from the
       known_faces DB table. Return {"removed":name, "known_count":total}.
     - Be safe against path traversal: sanitise `name` (no "/", "..", etc.).
  list_people(self) -> list[dict]:
     - [{"name":..., "photos":count, "sample":"<relative snapshot path or None>"}]
       derived from KNOWN_FACES_DIR + in-memory gallery. Include a way for the UI
       to show a thumbnail (see the /known_photo route below).

Keep identify() and existing return shapes unchanged.

--- 2) server.py — upload, delete, list, thumbnail routes ---
- POST "/enroll_upload"  (multipart/form-data):
    fields: name (str), files (one or MORE image files: jpg/png).
    - 400 if name empty or no files.
    - Sanitise name. Decode each uploaded file to a BGR image (cv2.imdecode on the
      bytes; reject non-images gracefully).
    - Call FaceModule.enroll_from_files(name, images).
    - Return the result dict (added, skipped reasons, known_count). Broadcast a
      refresh so the UI updates. 503 if FaceModule unavailable (ENABLE_FACE off).
- POST "/known/delete"  {"name": ...}:  FaceModule.remove_person(name) -> result.
- GET  "/known":  return FaceModule.list_people() (name + photo count) — extend the
    existing route if present, keep it backward-compatible.
- GET  "/known_photo/{name}":  return a representative saved photo for that person
    (FileResponse of the first image in KNOWN_FACES_DIR/<name>/), 404 if none.
    Sanitise name. This powers the thumbnail in the Known People list.
Return clean JSON on every error; never a stack trace. Reuse existing broadcast /
jsonify helpers.

--- 3) web UI — "Add Known Person" + "Known People" panels ---
Extend the existing Enroll area (do not remove the live-view "Enroll from Live
View" button — keep BOTH options):
  "Add Known Person (upload photos)":
    - A text input for the NAME.
    - A file input that accepts MULTIPLE images (accept="image/*" multiple).
    - An "Upload & Enroll" button -> POST /enroll_upload as FormData.
    - Show the result: "Added N photo(s) for <name>. Skipped: <reasons>." and any
      per-file warnings (no face / multiple faces).
    - Optional: show small previews of the selected files before upload (client-side
      FileReader), and a simple progress/disabled state while uploading.
  "Known People":
    - Fetch GET /known and render a list: thumbnail (GET /known_photo/<name>),
      name, photo count, and a "Delete" button -> POST /known/delete (with a
      confirm). Refresh the list after add/delete.
Vanilla JS, no CDN. Keep it consistent with the existing dark theme.

--- 4) Recognition cross-check (already works — just verify) ---
No pipeline change needed: once embeddings are in the gallery, the existing
/trigger face step cross-checks a new visitor against ALL enrolled embeddings and
names the best match above FACE_MATCH_THRESHOLD. Verify that an uploaded person is
then recognised. If matching feels too strict/loose, expose FACE_MATCH_THRESHOLD
(already in config) — do not hardcode.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. torch/YOLO unchanged (no install expected). Confirm.
2. Start app. In the dashboard, upload 1–3 photos of a person with a name via the
   new panel (for your test you may POST /enroll_upload with sample face image
   files — SAY which images). Paste the /enroll_upload response (added, known_count).
3. GET /known -> shows the new person + photo count; GET /known_photo/<name> ->
   returns an image (200).
4. Cross-check recognition: run /trigger on a DIFFERENT photo/frame of the SAME
   person -> event identity.known=true, name matches, reasonable confidence. Paste
   the event JSON. Then a stranger -> Unknown. (Reuse archived/sample images and
   say which, as in prior phases.)
5. Multi-photo: enrolling a 2nd photo under the same name increases photos count
   and adds another embedding (not a duplicate person). Confirm.
6. Delete: POST /known/delete for that name -> folder + embeddings + DB rows gone;
   GET /known no longer lists them; a subsequent /trigger returns Unknown for that
   face. Confirm.
7. Edge cases: upload a photo with NO face -> skipped with a clear reason, no
   crash; empty name -> 400; a non-image file -> handled gracefully.
8. Non-regression: live-view /enroll still works; Phases 1–12 behave (recognition,
   YOLO, anti-spoof, intent, Kokoro TTS, /trigger speed, richer descriptions,
   /status). Conservative language preserved.

====================================================================
GUARDRAILS
====================================================================
- REUSE FaceModule embedding logic; do not duplicate InsightFace code.
- Sanitise `name` everywhere it becomes a folder/file path (block "/", "..", null).
- Enrollment updates the IN-MEMORY gallery immediately (no restart) AND persists
  to disk + DB. A DB failure must not block the in-memory enroll.
- Multiple photos per person = multiple embeddings under one name (better matching),
  NOT multiple people.
- Clean JSON on every error path; never leak a stack trace to the client.
- No new pip installs; if any, keep torch 2.4.1 + verify YOLO.
- Do not rename VisitorEvent fields or existing DB methods. Keep the live-view
  enroll route working. Camera only via accessai/camera.py. Match existing style.

FIRST restate understanding + list files to modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## After it's done, send me a report with:
1. The `/enroll_upload` response after uploading photos with a name (added count,
   known_count).
2. `GET /known` showing the person + photo count, and `/known_photo/<name>`
   returning an image.
3. A `/trigger` event JSON proving a **different** photo of the same person is
   recognised by name (the cross-check), and a stranger → Unknown.
4. Delete working (person removed, then recognised as Unknown again).
5. Edge cases handled (no-face photo skipped, empty name 400) + Phases 1–12
   non-regression.

## How this works (the flow you described)
1. **Upload photos + name** → the panel POSTs the files to `/enroll_upload`.
2. **Face pattern analysed + saved** → InsightFace extracts a 512-D embedding from
   each photo, saved to `data/known_faces/<name>/` and the recognition gallery.
3. **Cross-check on arrival** → when someone rings, the existing `/trigger` face
   step compares their face against every stored embedding and names the best match
   above the threshold — which is already how recognition works, so uploaded people
   are recognised with no pipeline change.

**Tip:** upload **2–3 photos per person** from slightly different angles/lighting —
each adds an embedding under the same name and noticeably improves recognition
reliability. The prompt supports multi-file upload for exactly this reason.
