# PHASE 14 PROMPT — Mobile App (PWA over the existing FastAPI backend)

Builds the AccessAI mobile app as an installable PWA served by the existing
backend, usable on a phone over the same WiFi (no hardware needed). Paste
EVERYTHING in the fenced block below as your next message to the Claude agent in
VS Code.

---

```
You are building the AccessAI MOBILE APP. The Python/FastAPI backend (Phases 1–15)
is COMPLETE and working, with all endpoints. Build the app as a MOBILE-FIRST PWA
(Progressive Web App) SERVED BY the existing backend, consumed on a phone over the
same WiFi via the laptop's LAN IP. Do NOT rebuild backend AI logic — the app is a
thin client over the existing API. Do NOT break the existing desktop dashboard.

The app MUST surface the backend's newest capabilities (built in Phases 12/13/15):
  - MULTI-PERSON: an event carries a `people` list — show EVERY person, not one.
  - RICH UNKNOWN DESCRIPTIONS: age range, gender, hair, clothing colour, carried
    objects, apparent expression/mood — render these for unknown people.
  - PHOTO-UPLOAD ENROLLMENT: register known people by uploading photos + a name.
  - FAST, NO-RECORD DOORBELL: the doorbell does visual-only (fast); a SEPARATE
    "Hear Visitor" button is the only thing that records audio.

====================================================================
CONTEXT & DECISIONS (locked)
====================================================================
- App type: PWA now (Flutter later). Reuse the FastAPI backend + web stack.
- Connectivity: phone and laptop on the SAME WiFi; app talks to
  http://<laptop-LAN-IP>:8000. The app must let the user enter + save the server
  URL (persist in localStorage), defaulting to the same origin it was served from.
- Alerts: LIVE WebSocket while the app is open (build now). FCM background push =
  documented stub for later (do NOT implement FCM now).
- Users: the app is for the RESIDENT (blind or deaf), not the visitor. The mic is
  at the door (laptop/ESP32 side), so audio capture happens SERVER-SIDE via
  existing routes; the phone triggers them and displays results.

HONEST CONSTRAINT (handle it correctly):
- Service workers / installability require a SECURE CONTEXT (HTTPS or localhost).
  Over plain http://192.168.x.x the app must still FULLY WORK as a mobile web app
  (WebSocket alerts, live view, controls) — only offline-install is limited.
  Register the service worker with a guard so a non-secure context degrades
  gracefully (app works; SW just doesn't register). Document that HTTPS (e.g. a
  cloudflared tunnel) enables full install + is the path to FCM later.

====================================================================
STEP 0 — READ CURRENT CODE FIRST (reuse these endpoints)
====================================================================
Read the existing server routes so the app calls the REAL API:
- accessai/server.py — endpoints available (verify exact names/shapes):
    GET /video (MJPEG), POST /trigger (VISUAL ONLY — does NOT record audio),
    WS /events (broadcasts {"type":"event",...} and {"type":"visitor_speech"...}/
    {"type":"voice"...}), GET /history, GET /event/{id}, GET /snapshot/{id},
    GET/POST /mode, POST /reply, POST /hear_visitor (the ONLY audio-recording
    route — visitor speech -> caption), POST /listen (blind user's voice commands),
    GET /status, GET /voices + POST /voice, GET /known + GET /known_photo/{name} +
    POST /enroll_upload + POST /known/delete, GET /suggestions (+confirm/dismiss),
    /translate_status, /speech_status, etc.
- accessai/visitor_event.py — CONFIRM the event shape the app must render:
    `people` is a LIST; each person has {known, name, confidence, age, gender,
    box, is_spoof, spoof_score, appearance, expression}. Also top-level
    visitor_count, carried_objects, scene_summary, ocr_text, intent,
    announcement_text, speech_transcript, translated_transcript, snapshot_path.
    `identity` is the primary/first-known person (kept for backward compat) —
    but the app must render the FULL `people` list, not just identity.
- config.py, web/* (existing desktop dashboard — keep it intact).
Restate understanding in 3-4 bullets before coding. If an endpoint you need is
missing, ADD it minimally (see /command and /speak_audio below) without touching
existing ones.

====================================================================
WHAT TO BUILD
====================================================================

--- 1) Serve the PWA from the backend (new, alongside the desktop dashboard) ---
Create a NEW mobile app under web/app/ and serve it:
  web/app/
    index.html            # mobile-first single page
    app.js                # all client logic (vanilla JS, no CDN)
    app.css               # mobile dark theme, large touch targets
    manifest.webmanifest  # PWA manifest
    sw.js                 # service worker (app-shell cache; NETWORK-FIRST for API)
    icons/icon-192.png, icons/icon-512.png, icons/maskable-512.png
      (generate simple placeholder icons — a solid colour with a door/bell glyph;
       do NOT depend on external assets)
server.py routes (add; keep existing intact):
  - GET "/app"                 -> serve web/app/index.html
  - GET "/app/manifest.webmanifest" (correct MIME) and mount web/app as static so
    /app/app.js, /app/app.css, /app/sw.js, /app/icons/* load.
  - Serve sw.js at the /app/ scope so its controlled scope is /app/. Register it in
    app.js with navigator.serviceWorker.register('/app/sw.js', {scope:'/app/'})
    ONLY if 'serviceWorker' in navigator AND window.isSecureContext.
Make /app work when opened at http://<laptop-ip>:8000/app on a phone.

--- 2) App shell: bottom-nav, 4 tabs, mode-aware ---
Mobile layout with a bottom navigation bar and large, high-contrast controls:
  TAB 1 "Home":
    - Big status: the announcement text, time, and a snapshot thumbnail
      (GET /snapshot/{id}).
    - MULTI-PERSON CARD (render the FULL `people` list, never just one):
        * Show the reconciled count: e.g. "3 people — 1 known, 2 unknown".
        * KNOWN people: a green chip per name (+ small confidence).
        * UNKNOWN people: an amber card each, showing what's available —
          age range (from `age`, phrased as a range like "in their twenties",
          NEVER a raw number), gender, hair/clothing + colour + carried objects
          (`appearance`), and apparent mood (`expression`, hedged e.g.
          "appears calm"). If a person is `is_spoof`, mark them red "⚠ photo".
        * If `people` is empty but visitor_count>0, show "N visitor(s) detected".
    - A large "🔔 Test Ring" button (POST /trigger). LABEL/behaviour note: the
      doorbell is VISUAL-ONLY and FAST — it does NOT record audio. Do NOT show any
      "listening…" indicator for this button; it should feel instant.
    - A SEPARATE "🎤 Hear Visitor" button (POST /hear_visitor) — the ONLY control
      that records audio. Show a "🎤 Listening to visitor… (Ns)" indicator ONLY
      for this button. On result, show the transcribed + translated caption.
    - A "💬 Reply" input + send (POST /reply) -> spoken at the door (text->speech).
  TAB 2 "Live":
    - The live camera via <img src="{server}/video"> (MJPEG). A refresh/reconnect
      button (MJPEG can stall). Fit mobile screen.
  TAB 3 "History":
    - GET /history -> scrollable list: thumbnail, name(s), intent, time,
      announcement. For multi-person events, show the count + primary name(s)
      compactly (e.g. "Vinay +2"). Tap -> detail (GET /event/{id}) showing the
      full people list + descriptions.
  TAB 4 "Settings":
    - Server URL field (persist to localStorage; default = current origin; used as
      the base for ALL fetches + the WebSocket + /video). A "Test connection"
      button hitting GET /status.
    - Mode selector Blind / Deaf / Both (GET/POST /mode) — drives app behaviour
      (below).
    - Voice picker (GET /voices, POST /voice) with a "Test voice" (POST /reply
      "Hello, this is AccessAI.").
    - KNOWN PEOPLE MANAGEMENT (mirror the Phase-13 desktop enrollment):
        * List enrolled people from GET /known: thumbnail (GET /known_photo/<name>)
          + name + photo count + a "Delete" button (POST /known/delete, confirm).
        * "Add Known Person" form: a NAME input + a file input that accepts
          MULTIPLE images (accept="image/*" multiple) + an "Upload & Enroll" button
          that POSTs multipart to /enroll_upload. Show the result (added N photos,
          skipped reasons like "no face"). Refresh the list after add/delete.
        * Encourage 2–3 photos per person (a hint line) for better recognition.
    - System health summary from GET /status (green/amber per module).

--- 3) LIVE alerts over WebSocket (the core of a doorbell app) ---
- Open a WebSocket to {server}/events (ws:// or wss:// matching the origin scheme).
  Auto-reconnect with backoff if it drops. Show a connection indicator.
- On {"type":"event"} (a doorbell ring):
    * ALWAYS: show a prominent in-app ALERT (full-width card / overlay) with the
      visitor snapshot + announcement text + the MULTI-PERSON breakdown (known
      names as chips, each unknown described with age range / clothing colour /
      carried objects / mood — same rendering as the Home tab). Show a spoof flag
      for any is_spoof person.
    * DEAF or BOTH mode: strong visual flash + navigator.vibrate([300,120,300])
      (guard: vibrate may be a no-op on desktop / non-secure context) + a short
      alert SOUND (a bundled/oscillator beep so it works offline).
    * BLIND or BOTH mode: SPEAK the announcement ON THE PHONE (see #4) so the
      resident hears it on the device they're holding. (The backend announcement
      already enumerates all people, so speaking announcement_text is correct.)
- On {"type":"visitor_speech"}: update the caption area with the visitor's words +
  translation. On {"type":"voice"}: show the command Q/A.
- Keep the WebSocket handling resilient: never throw on an unknown message type.

--- 4) Phone-side spoken announcements (Blind mode) — natural voice ---
The server speaks on the LAPTOP; the resident holds the PHONE, so the phone should
also speak. Provide natural voice on the phone:
  PREFERRED: add a backend route GET "/speak_audio?text=..." that synthesises the
  text with the existing Kokoro TTS engine and returns WAV/MP3 audio bytes (reuse
  the TTS module's synth path; do the synth OFF the announcement worker so it
  doesn't disturb server-side speaking). The PWA plays it via an Audio element ->
  natural Kokoro voice on the phone.
  FALLBACK: if /speak_audio is unavailable or fails, use the browser Web Speech API
  (window.speechSynthesis) so the phone still speaks (robotic but functional).
  Gate all phone speech on Blind/Both mode. Never autoplay-block the demo: trigger
  an initial silent audio unlock on first user tap (mobile autoplay policy).

--- 5) Voice / text commands from the phone (nice-to-have, keep small) ---
Add backend POST "/command" {"text": "..."} that reuses the existing
voice_commands.parse_command + handle_command and returns {intent, answer}; speak
the answer via /speak_audio on the phone. In the app, a "🎙 Ask" button:
  - If window.SpeechRecognition/webkitSpeechRecognition exists, capture the
    resident's spoken command on the PHONE and send the text to /command.
  - Else, a text input ("who is at the door") -> /command.
This lets a blind user ask "who is at the door" from the phone. Keep it optional
and degrade gracefully if speech recognition isn't supported.

--- 6) PWA manifest + service worker (installable when on HTTPS/localhost) ---
- manifest.webmanifest: name "AccessAI", short_name, start_url "/app",
  display "standalone", background/theme colours (match the dark theme), the icons.
  Link it from index.html + apple-touch-icon + theme-color meta.
- sw.js: cache the APP SHELL (index.html, app.js, app.css, icons, manifest) for
  offline launch; use NETWORK-FIRST (or network-only) for /video, /events, and all
  /api-like GET/POSTs — NEVER cache camera frames, events, snapshots, or status.
  Handle install/activate/fetch cleanly; version the cache so updates take effect.
- Register the SW only in a secure context (guarded, per the constraint above).

--- 7) FCM background push — DOCUMENT ONLY (do not implement) ---
Add docs/MOBILE_PUSH.md describing the later FCM path: serve over HTTPS, add a
firebase-messaging-sw.js, register a device token via a new /register_push route,
and have the server POST to FCM on a doorbell event. Leave a clearly-marked TODO
stub (a no-op /register_push that stores a token) ONLY if trivial; otherwise just
document. Do NOT add Firebase deps now.

====================================================================
VERIFICATION — run and report ACTUAL output
====================================================================
1. No new heavy deps; if any install, confirm torch still 2.4.1 + YOLO bus.jpg
   detects. (This phase should need no ML installs.)
2. Start python3 run.py. Open http://localhost:8000/app in a browser (desktop is
   fine for verification; also give the exact phone URL form
   http://<laptop-ip>:8000/app and how to find the IP: `hostname -I`).
3. App loads: 4 tabs render; Settings shows/saves the server URL; Test connection
   hits /status and shows module health.
4. Live alert: trigger a doorbell (POST /trigger or the Test Ring button) with the
   app open -> the WebSocket alert fires: paste that it showed the event, and
   confirm Deaf mode flashed/vibrated and Blind mode spoke (via /speak_audio if you
   added it, else speechSynthesis). Report which speech path was used.
4b. MULTI-PERSON render: trigger an event with MORE THAN ONE person in view (or a
   test image with 2+ people, or reuse an event whose `people` list has 2+). Paste
   that the app rendered EVERY person — known chips + unknown descriptions
   (age range, clothing colour, carried objects, mood) — not just one. Confirm the
   count line ("N people — X known, Y unknown").
4c. NO-RECORD DOORBELL: confirm the Test Ring button shows NO "listening" indicator
   and returns fast, and that ONLY "Hear Visitor" shows the listening indicator +
   records. Report the observed doorbell response time.
5. Live view: /video renders in the Live tab (or reconnect works).
6. Two-way + enrollment: "Hear Visitor" (POST /hear_visitor) shows a caption;
   "Reply" (POST /reply) is spoken at the door. In Settings, UPLOAD 2+ photos of a
   person with a name (POST /enroll_upload) -> they appear in Known People with a
   thumbnail + photo count; Delete removes them. Paste the enroll result.
7. PWA: on localhost (secure context) confirm the service worker registers and the
   manifest is valid (installable / add-to-home-screen prompt). Over plain-HTTP LAN,
   confirm the app STILL WORKS and the SW registration is skipped gracefully (no
   errors). Report both.
8. Non-regression: the DESKTOP dashboard at / still works; all existing endpoints
   unchanged; Phases 1–15 behave. Conservative language preserved.

====================================================================
GUARDRAILS
====================================================================
- The app is a THIN CLIENT: reuse existing endpoints; only add /speak_audio,
  /command, (optional) /register_push. Do NOT duplicate AI logic or rename things.
- Everything keyed off a configurable server base URL (localStorage), defaulting to
  the serving origin, so the SAME app works on the phone via the LAN IP.
- Service worker registers ONLY in a secure context; the app must fully work
  without it over HTTP LAN. Never cache live/dynamic endpoints.
- Mobile autoplay: unlock audio on first tap so Blind-mode speech works.
- Guard vibrate/speech/SpeechRecognition for unsupported browsers — degrade, never
  crash.
- Keep the desktop dashboard at / intact. Vanilla JS, no CDN, no build step.
- No new ML installs; if any install at all, verify torch 2.4.1 + YOLO after.
- Match existing code style; clean JSON on new endpoints' errors.
- MULTI-PERSON: always render the FULL `people` list; never collapse to one
  person. KNOWN = name chip only; UNKNOWN = rich description. Age as a RANGE,
  expression hedged ("appears ..."), never "definitely".
- DOORBELL = visual-only + fast (no audio, no listening indicator). Audio recording
  happens ONLY via the separate "Hear Visitor" button. Do not merge the two.
- ENROLLMENT: support MULTIPLE photos per person in one upload; show skipped
  reasons; refresh the known list after add/delete.

FIRST restate understanding + list files to create/modify (and any new endpoints).
THEN build. THEN run verification and report real output, fixing errors before
finishing.
```

---

## After it's done, send me a report with:
1. The exact phone URL to open (`http://<laptop-ip>:8000/app`) + how you found the
   IP (`hostname -I`).
2. Confirmation the 4 tabs work and Settings saves/uses the server URL.
3. A live WebSocket alert firing on a doorbell ring (Deaf flash/vibrate + Blind
   spoke) — and which phone-speech path was used (`/speak_audio` Kokoro vs browser).
4. **Multi-person render** proof: an event with 2+ people showed EVERY person
   (known names + unknown descriptions with age range / clothing colour / objects /
   mood), plus the count line.
5. **Fast no-record doorbell** confirmed (no listening indicator, quick) vs the
   separate **Hear Visitor** which records — with the observed doorbell time.
6. **Photo-upload enrollment** from the app (2+ photos + name) → appears in Known
   People; Delete works.
7. PWA status: SW registered on localhost; graceful skip over HTTP LAN; desktop
   dashboard + Phases 1–15 non-regression.

## How to actually run it on your phone (do this after the build)
1. On the laptop: `hostname -I` → note the address like `192.168.1.42`.
2. Phone on the **same WiFi** → open `http://192.168.1.42:8000/app`.
3. Settings tab → confirm the server URL, pick Blind/Deaf/Both, choose a voice.
4. Press "Test Ring" (or have someone at the webcam) → the phone alerts live.

## What's now demoable without any hardware
- Laptop = the "door unit" (camera + mic + AI + speaker).
- Phone = the resident's app: live alerts, who's at the door (spoken in the natural
  Kokoro voice), Deaf captions + vibration, two-way reply, history, enrollment.
- When the ESP32 arrives, you change **one line** (`CAMERA_SOURCE`) and the app
  doesn't change at all.

## The "later" upgrades this sets up
- **HTTPS** (free cloudflared tunnel) → full PWA install + unlocks **FCM push** so
  it alerts even when the app is closed (documented in `docs/MOBILE_PUSH.md`).
- **Flutter** → if you still want a native app, it's a thin client over the exact
  same endpoints this PWA already proves.
