# PHASE 15 PROMPT — Multi-Person Recognition + Rich Per-Person Description

Fixes a real limitation: when several people are at the door, the system only
announces ONE. Make it recognise and announce EVERY person — known ones by name,
unknown ones with a rich description (appearance, clothing colour, approximate
age, carried objects, apparent expression). Paste EVERYTHING in the fenced block
below as your next message to the Claude agent in VS Code.

---

```
You are enhancing the completed AccessAI project (Phases 1–14 done, working). Build
ONLY this: MULTI-PERSON handling. Today the pipeline picks the single LARGEST face
and announces one person even when several are present (observed live: YOLO found
3 persons, but it only said "Vinay is at the door"). Fix it so ALL people are
recognised and described. Do NOT break existing single-person behaviour.

====================================================================
DESIRED BEHAVIOUR (the whole point)
====================================================================
When N people are at the door:
- Recognise EVERY detected face, not just the largest.
- KNOWN people -> name each AND describe them too (clothing, carried objects,
  apparent mood) — e.g. "Vinay is at the door, wearing a black shirt, carrying a
  backpack, appears cheerful." Two known: "Vinay and Sajeevan are at the door.
  Vinay is wearing a black shirt; Sajeevan is in a blue jacket carrying a bag."
  (For KNOWN people, do NOT announce age/gender — we already know who they are —
   but DO include clothing / carried objects / mood.)
- UNKNOWN people -> describe each conservatively: approx age RANGE, gender, hair,
  clothing (type + colour), carried objects, and apparent expression/mood.
- MIXED -> name+describe the known, then describe the unknown(s):
  "Vinay is at the door, wearing a black shirt, along with one unknown visitor:
   a man in his twenties with short dark hair, wearing a blue jacket, carrying a
   backpack, appears calm."
- Reconcile counts: YOLO 'person' count may exceed detected faces (people turned
  away / partially visible). People with no recognisable face are counted as
  additional unknown visitors ("and 2 other people").
- Keep it to a natural 1–3 sentences; never fabricate details; stay conservative
  ("appears", "looks like", never "definitely").

NOTE — VLM now runs for KNOWN people too. Earlier phases SKIPPED the VLM for known
faces to save latency/cost. Per an explicit product decision, the VLM now
describes EVERYONE (known + unknown) so a blind user hears what a recognised
person is wearing / carrying. This adds one VLM call to known-only scenes. It is
behind a config flag (VLM_DESCRIBE_KNOWN, default True) so it can be turned off.

====================================================================
TORCH SAFETY
====================================================================
No new pip install is needed. Age/gender is the InsightFace genderage model
(already enabled in Phase 12). Appearance + expression come from the EXISTING VLM
(reused). Emotion is a VISUAL inference via the VLM, NOT a new model, and is framed
cautiously. If you think you need a new dependency, you don't. If you install
anything, verify torch is still 2.4.1 and YOLO bus.jpg still detects.

NOTE on "emotion": we previously dropped AUDIO emotion as unreliable. This is
different — a cautious VISUAL expression cue from the VLM ("appears calm/worried"),
always hedged. Keep it optional and conservative.

====================================================================
STEP 0 — READ CURRENT CODE FIRST
====================================================================
Read fully before changing:
- accessai/visitor_event.py  (VisitorEvent has single `identity: Identity`,
                             `visitor_count`, `age`, `gender`, `appearance`,
                             `detected_objects`, `carried_objects`; add a `people`
                             list — do NOT remove `identity`)
- accessai/face_module.py    (identify() returns ALL faces already:
                             [{name, confidence, box, det_score, (age, gender)}];
                             confirm age/gender per face from Phase 12)
- accessai/pipeline.py       (currently: best = max(faces, key=area); sets ONE
                             identity. Anti-spoof on the one face. VLM for unknown.
                             THIS is what becomes multi-person.)
- accessai/vlm_module.py     (describe_and_read: richen to enumerate PEOPLE with
                             per-person attributes incl. expression; ONE call)
- accessai/antispoof.py      (score(frame, box) -> run per known face)
- accessai/context_engine.py (infer_intent — keep pure; handle "any known present")
- accessai/accessibility.py  (compose_announcement — REWRITE the who-clause to
                             enumerate multiple people)
- accessai/database.py       (store the people list as JSON — add a column safely)
- accessai/server.py, web/app.js + web/app/app.js (render multiple people)
Restate understanding in 3-4 bullets before coding.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) visitor_event.py — a people list (keep identity for compat) ---
Add a Person dataclass and a people field:
  @dataclass
  class Person:
      known: bool = False
      name: str = "Unknown"
      confidence: float = 0.0
      age: int | None = None
      gender: str = ""            # "man"/"woman"/""
      box: tuple = (0,0,0,0)
      is_spoof: bool = False
      spoof_score: float = 1.0
      appearance: str = ""        # VLM per-person description (unknowns)
      expression: str = ""        # cautious mood cue (unknowns), e.g. "calm"
  VisitorEvent: add  people: list = field(default_factory=list)
  Keep `identity` (set it to the FIRST known person, else the largest face) so all
  existing code + fields keep working. Keep age/gender/appearance top-level too
  (mirror the primary person) for backward compatibility.

--- 2) face_module.py — ensure per-face age/gender ---
Confirm identify() returns age + gender for EACH face (from the genderage model
enabled in Phase 12). If it only sets them for the largest, extend so every face
in the returned list carries its own age/gender/box. Do NOT change existing keys.

--- 3) pipeline.py — process ALL faces + reconcile counts ---
Replace the "largest face only" logic with multi-person logic:
  faces = self.face.identify(frame) if face enabled     # list, each w/ name/box/age/gender
  people = []
  for f in faces:
      p = Person(known=(f["name"]!="Unknown"), name=f["name"],
                 confidence=f.get("confidence",0.0), age=f.get("age"),
                 gender=map_sex(f.get("gender")), box=tuple(f["box"]))
      # Anti-spoof per face (esp. for known): if spoof, downgrade THIS person to unknown
      if antispoof enabled and p.box != (0,0,0,0):
          p.spoof_score = float(self.antispoof.score(frame, p.box))
          p.is_spoof = not self.antispoof.is_live(p.spoof_score)
          if p.is_spoof and p.known:
              p.known = False; p.name = "Unknown"
      people.append(p)
  # Reconcile with YOLO person detections (Phase 3): people whose face wasn't
  # detected still count as visitors.
  person_boxes = [d for d in ev.detected_objects if d.label == "person"]
  face_count = len(people)
  yolo_person_count = len(person_boxes)
  extra_unrecognised = max(0, yolo_person_count - face_count)  # faces not detected
  ev.people = people
  ev.visitor_count = max(face_count + 0, yolo_person_count)     # total humans
  ev._extra_unknown = extra_unrecognised   # (or pass into accessibility a count)
  # Backward-compat primary identity:
  known_people = [p for p in people if p.known]
  primary = known_people[0] if known_people else (people[0] if people else None)
  if primary: ev.identity = Identity(known=primary.known, name=primary.name,
                                     confidence=primary.confidence)
  if primary: ev.age, ev.gender = primary.age, primary.gender

VLM step (describe EVERYONE — known AND unknown): call the VLM ONCE to describe all
visible people (see #4) whenever there is at least one person AND the VLM is
available, gated by config:
  run_vlm = vlm.available() and (
      any(unknown person OR extra_unrecognised>0)          # always describe unknowns
      or (config.VLM_DESCRIBE_KNOWN and any known person)  # NEW: describe known too
  )
Then MAP the returned per-person descriptions back to the Person entries so EACH
person (known or unknown) gets appearance + expression:
  - Sort ev.people by the horizontal centre of their box (x-centre, left→right).
  - Sort the VLM `people` descriptions in the SAME left→right order if the VLM
    provides positions; otherwise zip by index order (best-effort).
  - Assign each description's appearance/carrying/expression to the matching
    Person (set p.appearance and p.expression; fold "carrying" into appearance or
    a per-person carried list). Any leftover / overall text -> ev.scene_summary.
  - If mapping is uncertain (counts differ), fall back gracefully: still attach
    descriptions to unknowns first, then to known, and never crash on mismatch.
If VLM_DESCRIBE_KNOWN is False (or no key), known people get NAME ONLY (as before)
and only unknowns are described — preserving the old latency win when desired.

Add a helper map_sex("M"/"F") -> "man"/"woman"/"".

--- 4) vlm_module.py — describe MULTIPLE people (one call) ---
Update the combined prompt to return, as compact JSON, a LIST of people (ordered
LEFT→RIGHT as they appear) plus scene + labels, e.g.:
  {"people":[
     {"position":"left","appearance":"man in his twenties, short dark hair, black
      t-shirt","carrying":"a backpack","expression":"calm"},
     {"position":"right","appearance":"woman, floral top","carrying":"",
      "expression":"neutral"}],
   "scene":"two people standing at the door",
   "labels":"BLUEDART ..."}
System prompt: "Describe EACH visible person for a blind resident, ordered from
LEFT to RIGHT as they appear in the image. For each person: approximate age range,
gender if clear, hair, clothing type + main colours, any uniform, carried objects,
and apparent facial expression/mood — cautiously ('appears calm'). Be brief and
factual; never guess a person's NAME/IDENTITY; never say 'definitely'. Return ONLY
the JSON." The description is used for BOTH known and unknown people (the app pairs
the NAME from face recognition with this appearance), so the VLM must NOT try to
identify anyone — only describe. Parse defensively; on failure return empty lists
so the system falls back to face-only age/gender. Keep the multi-key failover +
single call. The left→right `position`/order is what lets the pipeline map each
description to the right face box.

--- 5) accessibility.py — enumerate people in the announcement ---
Rewrite the WHO clause of compose_announcement to build from ev.people (+ the
extra-unknown count). Rules:
  known = [p for p in ev.people if p.known and not p.is_spoof]
  unknown_faces = [p for p in ev.people if not p.known]
  extra = <extra_unrecognised count passed from pipeline>
  total_unknown = len(unknown_faces) + extra
  Build a natural sentence:
   - Known names: join with commas + "and" ("Vinay", "Vinay and Sajeevan",
     "Vinay, Ravi and Sajeevan").
   - If only known: "<names> is/are at the door."
   - If only unknown: "<M> unknown visitor(s) at the door." then for EACH unknown
     face with a description: " One is <appearance>, carrying <x>, appears <mood>."
     (limit to describing up to ~2–3 in speech; if more, summarise "and N others").
   - If mixed: "<known names> is/are at the door, along with <M> unknown
     visitor(s): <descriptions>."
   - Spoof among them: prepend/append a caution for any spoofed face.
  Then keep the existing tail: carried objects (overall), likely delivery, label
  reads (OCR), and visitor speech ("They said ...").
  Use conservative age RANGE phrasing (reuse the Phase-12 age-range helper) for any
  unknown person whose age came from InsightFace. Never exceed ~3 sentences; if the
  crowd is large, summarise gracefully. KNOWN people never get age/gender in the
  announcement.

--- 6) database.py — persist the people list ---
Add a `people` JSON text column to the events table (json.dumps(list of Person
dicts)). Use an ADDITIVE approach; note that SQLAlchemy create_all won't ALTER an
existing table, so either add a tiny migration (ALTER TABLE ... ADD COLUMN if
missing, in try/except) or instruct that a fresh DB is created. _event_row_to_dict
should include people (json.loads, default []). Do NOT rename existing columns.

--- 7) web UI — show every person ---
- Desktop dashboard (web/app.js) AND the mobile app (web/app/app.js): the Current
  Visitor card lists EACH person: a chip per known name (green) and a described
  card per unknown (amber) with age/gender/appearance/carrying/expression. Show the
  reconciled total count ("3 people: 1 known, 2 unknown"). History too (compact).
- Keep the existing single-person rendering working when there's one person.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. Torch/YOLO unchanged (no install expected). Confirm.
2. TWO KNOWN people: enrol two people; put both in frame (or use two archived
   faces composited / two sample images — SAY which). /trigger -> event.people has
   2 entries both known; announcement: "<A> and <B> are at the door." Paste JSON +
   announcement.
3. ONE KNOWN + ONE UNKNOWN: -> announcement names the known and DESCRIBES the
   unknown (age range, clothing colour, carried object, expression). Paste JSON +
   announcement.
4. TWO+ UNKNOWN: -> each described; if some faces aren't detected but YOLO sees
   more persons, the count reconciles ("and N other people"). Paste JSON.
5. Count reconciliation: a frame where YOLO person_count > detected faces -> extra
   people are counted as unknown visitors. Report the numbers.
6. Spoof-in-crowd: a real known person + a photo of someone -> the photo person is
   downgraded to unknown/spoof, the real person still named. (Deterministic stub OK
   — say so.)
7. Non-regression: single known person still says "<Name> is at the door."; single
   unknown still gets the Phase-12 rich description; KNOWN-only scenes still SKIP
   the VLM (latency); Kokoro TTS speaks it; /status, Deaf mode, translation intact.
   Conservative language preserved.

====================================================================
GUARDRAILS
====================================================================
- Recognise + describe ALL people; never silently drop anyone. Cap SPOKEN detail
  at ~2–3 described unknowns, summarising the rest ("and N others") so speech
  stays usable.
- KNOWN people: name only (no age/gender/appearance in speech). UNKNOWN: rich
  description. Spoofed known face -> treated as unknown.
- Age is always a RANGE; expression is always hedged ("appears ..."); never
  "definitely".
- One VLM call per event (cost); KNOWN-only scenes make NO VLM call.
- Keep `identity` set to the primary known (or largest) person for backward compat.
- No new installs; if any, verify torch 2.4.1 + YOLO. context_engine stays pure.
- Do not rename existing VisitorEvent fields or DB columns (ADD only). Camera only
  via accessai/camera.py. Match existing style.

FIRST restate understanding + list files to modify. THEN build. THEN run
verification and report real output, fixing errors before finishing.
```

---

## After it's done, send me a report with:
1. **Two known people** → event JSON with 2 known entries + "A and B are at the
   door."
2. **One known + one unknown** → the known named, the unknown described (age range,
   hair, clothing colour, carried object, expression).
3. **Two+ unknown** → each described, and count reconciliation when YOLO sees more
   people than faces.
4. Spoof-in-crowd handled; single-person non-regression; KNOWN-only still skips VLM.
5. Torch/YOLO unchanged; Phases 1–14 intact.

## What this fixes and adds
- **The bug you saw:** it will now announce *every* person, not just the largest
  face — two known people get both names.
- **The richness you asked for:** unknown people get hair, dress colour, age range,
  carried objects, and a cautious mood cue — all from models you already have
  (InsightFace age/gender + the VLM), so **no new installs and torch stays safe**.

## One honest note on the pieces
- **Age/gender** (InsightFace) is approximate — the prompt always speaks it as a
  range ("in his twenties"), never an exact number.
- **Expression/emotion** is a *visual* cue from the VLM, always hedged ("appears
  calm"). It needs a VLM key to be active; with no key, you still get names + age +
  clothing/objects from local models, just not the mood line.
- Describing many unknowns aloud gets long, so speech caps at ~2–3 described and
  summarises the rest ("and 3 others") — the full detail is still in the event/UI.

Go build it, then send the report. This is the fix that makes a **group at the
door** work properly — genuinely important for a real doorbell.

