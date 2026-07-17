# PHASE 16 PROMPT — Native Flutter App (award-winning, animated, accessibility-first)

The ONE detailed prompt to build the AccessAI native mobile app in Flutter, over
the existing FastAPI backend. Paste EVERYTHING in the fenced block below as your
next message to the Claude agent in VS Code. (Flutter is NOT installed yet — the
prompt installs it.)

---

```
You are building the AccessAI NATIVE MOBILE APP in FLUTTER. The Python/FastAPI
backend (Phases 1–15) is COMPLETE and working with all endpoints, and a PWA
already exists. Now build a polished, animated, AWARD-WINNING, ACCESSIBILITY-FIRST
native Flutter app that is a THIN CLIENT over the existing API. Do NOT rebuild any
backend AI logic. Do NOT break the backend or the existing web/PWA.

Work in a NEW folder `mobile/` (a Flutter project) inside the repo, so the Python
app is untouched. Build for ANDROID first (the dev machine is Linux; no Mac/iOS).

====================================================================
0) TOOLING — INSTALL FLUTTER (it is NOT installed) + use the design skills
====================================================================
- Detect the OS/arch. On this Linux machine, install Flutter (stable channel):
    * Download the Flutter SDK (stable) to ~/flutter (git clone the stable branch:
      `git clone https://github.com/flutter/flutter.git -b stable ~/flutter`),
      add `~/flutter/bin` to PATH (append to ~/.bashrc), then run `flutter --version`.
    * Install the Android toolchain: Android Studio OR the command-line SDK +
      platform-tools; run `flutter doctor` and resolve what you can automatically
      (accept licenses: `flutter doctor --android-licenses`). If a piece needs
      manual GUI steps, STOP and print a short, exact checklist for the user, then
      continue with whatever `flutter doctor` allows.
    * For quick iteration, enable web too (`flutter config --enable-web`) so you can
      run `flutter run -d chrome` when no device/emulator is attached; but the
      PRIMARY target is a physical Android phone over Wi-Fi.
- USE THE DESIGN SKILLS/MCP that are installed in this VS Code Claude extension:
    * Use the `ui-ux-pro-max` skill for UX/interaction/design-system decisions
      (hierarchy, motion, color, accessibility patterns) — consult it as you design
      each screen.
    * You may use the 21st.dev (Magic) MCP for VISUAL REFERENCE / design ideas.
      IMPORTANT: 21st.dev emits React/Tailwind, NOT Flutter — do NOT paste its code.
      Translate its design ideas into idiomatic Flutter widgets. If the MCP is
      unavailable in a headless run, proceed with the ui-ux-pro-max skill alone.
Restate your understanding + your screen/architecture plan in a short list BEFORE
coding.

====================================================================
1) BACKEND API — the app consumes these (verify exact shapes in accessai/server.py)
====================================================================
- GET  /video                      MJPEG live stream (multipart/x-mixed-replace)
- POST /trigger                    doorbell: VISUAL ONLY, FAST, NO audio recording
- WS   /events                     broadcasts {"type":"event",...},
                                   {"type":"visitor_speech",...}, {"type":"voice",...}
- GET  /history?limit=N            past events (newest first)
- GET  /event/{id}                 one event
- GET  /snapshot/{id}              event snapshot JPEG
- GET/POST /mode                   "blind" | "deaf" | "both"
- POST /reply           {text}     text -> spoken at the door
- POST /hear_visitor               THE ONLY audio-recording route (visitor speech
                                   -> transcript + translation)
- POST /listen                     blind user's on-device-independent voice command
- POST /command         {text}     parse+run a command, returns {intent, answer}
- GET  /speak_audio?text=...       returns natural Kokoro TTS AUDIO bytes (wav/mp3)
- GET  /voices  + POST /voice {id} list/select TTS voice
- GET  /known  + GET /known_photo/{name}
- POST /enroll_upload  (multipart: name + one or MORE image files)
- POST /known/delete   {name}
- GET  /suggestions (+ /suggestions/confirm, /suggestions/dismiss)
- GET  /status                     full module health JSON (+ torch version)
- GET  /translate_status, /speech_status, /reid_status, /vlm_status, /wakeword_status

EVENT SHAPE the app MUST render (from accessai/visitor_event.py):
  people: LIST; each {known, name, confidence, age, gender, box, is_spoof,
    spoof_score, appearance, expression}. Plus: visitor_count, carried_objects,
    scene_summary, ocr_text, intent, announcement_text, speech_transcript,
    translated_transcript, snapshot_path, timestamp, event_id. `identity` is the
    primary/first-known person (compat) — but RENDER THE FULL people LIST.
NOTE: known AND unknown people both carry appearance/expression now (VLM describes
everyone). Show name for known; show rich description (age range, hair, clothing
colour, carried objects, mood) for all.

If a small endpoint you need is missing, ADD it minimally to server.py WITHOUT
touching existing routes. Enable CORS on the backend for the app origins
(localhost, the LAN IP) if not already enabled.

====================================================================
2) CONNECTIVITY (same Wi-Fi, laptop is the server)
====================================================================
- All network calls use a CONFIGURABLE server base URL (e.g. http://192.168.x.x:8000),
  entered in-app and persisted (shared_preferences). Default to a sensible LAN
  guess or a first-run setup screen. Build the WebSocket URL + /video + all REST
  from this base.
- ANDROID CLEARTEXT HTTP GOTCHA (must handle): Android blocks plain http:// by
  default. Add a network security config (res/xml/network_security_config.xml)
  permitting cleartext to private LAN ranges (or set usesCleartextTraffic=true for
  dev), and reference it in AndroidManifest. Add INTERNET permission. Without this
  the app cannot reach the laptop — do NOT skip this.
- A "Test connection" action hits GET /status and shows module health.

====================================================================
3) DESIGN LANGUAGE — award-winning BUT accessibility-first (resolve the tension)
====================================================================
This is an assistive product for BLIND and DEAF users. "Award-winning" here means
BEAUTIFUL *and* deeply usable by them. Non-negotiables:
- Full screen-reader support: wrap meaningful widgets in Semantics with clear
  labels; announcements via SemanticsService.announce for live events; logical
  focus order. Test with TalkBack in mind.
- HUGE touch targets (>= 64dp for primary actions), generous spacing, big scalable
  text that respects the system text-scale factor (never hardcode tiny fonts).
- High-contrast, WCAG-AA color; a proper light AND dark theme; a high-contrast
  variant.
- Haptics for Deaf users (HapticFeedback + rich vibration patterns); visual flash
  + captions for Deaf; spoken output for Blind.
- MOTION SAFETY: gorgeous motion by default, but HONOR the OS "reduce motion"
  setting (MediaQuery.disableAnimations / accessibleNavigation) — when on, disable
  parallax/3D/auto-motion and use instant or minimal transitions. Motion must NEVER
  gate functionality.
Visual direction (make it stunning within those rules):
- A cohesive design system (spacing scale, radii, elevation, a signature accent).
- Tasteful depth: glassmorphism (BackdropFilter blur), soft neumorphic cards,
  gradient meshes, subtle parallax that responds to device tilt (sensors) —
  all gated by reduce-motion.
- A signature animated hero: a 3D / richly-animated "smart doorbell" centerpiece.
  Use `rive` (preferred for interactive vector/'3D-feel' animation) and/or `lottie`;
  for a TRUE 3D model use `model_viewer_plus` (renders a .glb) or
  `flutter_3d_controller` as an optional flourish — keep it lightweight and
  reduce-motion aware. If you can't source a 3D asset, achieve depth with layered
  parallax + shaders/gradients rather than blocking the build.
- Micro-interactions with `flutter_animate` (button press ripples, staggered list
  reveals, number count-ups, shimmer while loading).
- Hero transitions between list and detail; smooth shared-element snapshots.
- A distinctive full-screen DOORBELL ALERT animation (pulse/ripple + snapshot
  reveal) when an event arrives.

====================================================================
4) ARCHITECTURE (clean, idiomatic Flutter)
====================================================================
- State management: Riverpod (or Provider) — pick Riverpod. Repositories/services
  for Api (REST via dio), Events (WebSocket via web_socket_channel), Audio, Prefs.
- A typed model layer mirroring the event shape (VisitorEvent, Person, etc.) with
  JSON (de)serialization (json_serializable or manual — keep it simple, no codegen
  headaches if it slows you down).
- App-wide Mode (blind/deaf/both) drives behaviour and is synced with GET/POST /mode.
- Graceful, non-crashing everywhere: network errors show friendly retry UI; unknown
  WebSocket message types are ignored; missing fields default sensibly.

====================================================================
5) SCREENS / FEATURES (all existing capabilities, beautifully)
====================================================================
Use a modern nav (animated bottom nav or a rail on large screens):

HOME / "Door":
- The animated doorbell hero centerpiece.
- Latest event card rendering the FULL multi-person breakdown:
    * a count line ("3 people — 1 known, 2 unknown"),
    * KNOWN: name chip + their appearance (clothing/carried/mood) — NO age/gender,
    * UNKNOWN: a rich card with age RANGE (never a raw number), gender, hair,
      clothing + colour, carried objects, apparent mood; spoofed faces flagged red
      "⚠ photo",
    * the announcement_text, timestamp, and a hero-animated snapshot.
- A big "🔔 Ring" button (POST /trigger) — VISUAL-ONLY + FAST; NO listening
  indicator; delightful press animation + success haptic.
- A SEPARATE "🎤 Hear Visitor" button (POST /hear_visitor) — the ONLY audio
  recorder; shows a "listening… (Ns)" animated indicator; renders the caption +
  translation.
- A "💬 Reply" composer (POST /reply) — spoken at the door; quick-reply chips
  ("Leave it at the gate", "Coming", "Please wait").

LIVE:
- The MJPEG live view (use `flutter_mjpeg` or a robust multipart Image widget) with
  a reconnect control; fit + rounded, framed nicely; a subtle scanline/gradient
  overlay (reduce-motion aware).

HISTORY:
- A gorgeous, staggered list of past events (thumbnail, name(s) e.g. "Vinay +2",
  intent, time). Tap -> detail with the full people breakdown + snapshot hero
  transition. Pull-to-refresh.

PEOPLE (enrollment & management):
- Grid/list of known people from GET /known with thumbnails (GET /known_photo/<name>),
  photo counts, and delete (POST /known/delete, confirm).
- "Add person": name + pick MULTIPLE photos (image_picker) -> POST /enroll_upload
  (dio multipart). Show per-file results (added / "no face"), a progress animation,
  and a hint to add 2–3 photos for accuracy.

SETTINGS:
- Server URL (persisted) + Test connection (GET /status) with an animated health
  panel (green/amber per module; flag placeholders + missing VLM keys).
- Mode selector Blind / Deaf / Both (GET/POST /mode) with a clear, animated toggle
  that visibly changes the app's behaviour.
- Voice picker (GET /voices, POST /voice) + "Test voice" (POST /reply sample).
- Language display (from /translate_status).
- Theme: light/dark/high-contrast; text-size respect note; a "reduce motion"
  status reflecting the OS setting.

LIVE ALERTS (the heart of a doorbell app) — over the /events WebSocket:
- Keep a persistent WebSocket (with backoff reconnect + a connection indicator).
- On {"type":"event"}: a full-screen or top-sheet ALERT with the snapshot + the
  multi-person breakdown + announcement.
    * DEAF or BOTH: strong visual flash + rich vibration pattern + a caption; NO
      reliance on sound.
    * BLIND or BOTH: SPEAK the announcement on the PHONE — fetch GET /speak_audio
      ?text=<announcement> and play the natural Kokoro audio via `just_audio`;
      FALLBACK to `flutter_tts` if that fails. Also SemanticsService.announce it
      for TalkBack. (Unlock/allow audio playback appropriately.)
- On {"type":"visitor_speech"}: show the caption (+ translation). On {"type":"voice"}:
  show the command Q/A.

VOICE COMMANDS (blind-first, optional but include):
- A prominent "Ask" mic button. If on-device speech recognition is available
  (`speech_to_text` package), capture the user's phrase on the PHONE and POST /command
  {text}; else a text field. Speak the returned answer via /speak_audio. Commands
  like "who is at the door", "recent visitors", "open live", "switch to deaf mode".

====================================================================
6) PACKAGES (pin reasonable versions; keep the set lean)
====================================================================
State: flutter_riverpod. Network: dio, web_socket_channel. Storage:
shared_preferences. Media: just_audio (Kokoro playback), flutter_mjpeg (live view),
flutter_tts (fallback speech), speech_to_text (optional on-device commands),
image_picker (enrollment photos), vibration (Deaf patterns). Motion/visuals:
flutter_animate, rive and/or lottie, model_viewer_plus (optional 3D), google_fonts,
shimmer (or flutter_animate shimmer). Sensors (optional parallax): sensors_plus.
Prefer fewer packages if any won't build cleanly on the current Flutter stable.

====================================================================
7) VERIFICATION — run and report ACTUAL output
====================================================================
1. `flutter --version` + a trimmed `flutter doctor` (note any manual steps the user
   must finish). Confirm the project builds: `flutter analyze` clean (fix issues)
   and `flutter build apk --debug` succeeds (or `flutter run -d chrome` if no
   device). Report which target you verified on.
2. Connectivity: set the server URL to the laptop LAN IP; Test connection shows the
   /status health. Confirm Android cleartext-HTTP config is in place.
3. Live alert: with the app open, POST /trigger on the backend -> the WebSocket
   alert fires; Deaf flash+vibrate; Blind plays Kokoro audio from /speak_audio (or
   flutter_tts fallback) AND SemanticsService.announce. Report which speech path ran.
4. Multi-person: an event with 2+ people renders EVERY person (known chips + rich
   unknown/known descriptions, count line). Paste a screenshot description or the
   rendered fields.
5. Doorbell is fast + NO recording (no listening indicator); "Hear Visitor" is the
   only recorder and shows the caption. Report the observed doorbell responsiveness.
6. Enrollment: pick 2+ photos + name -> /enroll_upload -> appears in People; delete
   works. Live view renders; History list + detail hero transition work.
7. ACCESSIBILITY: confirm Semantics labels on key controls, huge touch targets,
   text scales with system setting, and MOTION is disabled when the OS reduce-motion
   / disableAnimations flag is on. Report how you verified (e.g. toggling
   MediaQuery.disableAnimations).
8. Non-regression: the Python backend, desktop dashboard, and PWA are untouched and
   still work. No backend AI logic duplicated.

====================================================================
8) GUARDRAILS
====================================================================
- Thin client: reuse existing endpoints; only ADD tiny endpoints if strictly
  needed; never duplicate AI logic or rename backend things.
- Build in `mobile/`; do not disturb the Python app, web/, or web/app/ (PWA).
- Everything keyed off the configurable server base URL (persisted).
- ACCESSIBILITY IS A HARD REQUIREMENT, not optional polish: Semantics, big targets,
  scalable text, haptics, captions, spoken output, and reduce-motion support.
  Beautiful 3D/motion must DEGRADE gracefully and never block a blind/deaf user.
- KNOWN people: name + appearance (clothing/objects/mood), NO age/gender. UNKNOWN:
  full description with age as a RANGE, expression hedged ("appears ..."). Never
  "definitely".
- Doorbell = visual-only + fast (no audio); audio ONLY via "Hear Visitor". Do not
  merge them.
- Handle the Android cleartext-HTTP requirement (app can't reach the LAN server
  otherwise). Add INTERNET permission.
- Never crash on network/WebSocket/parse errors — friendly retry + sensible
  defaults. Unknown WS message types ignored.
- If `flutter doctor` needs GUI/manual steps you can't do headless, STOP and give
  the user an exact short checklist, then continue with what's possible.

FIRST: install Flutter + restate your screen/architecture plan and the package
list. THEN scaffold `mobile/` and build screen-by-screen (Home/alerts first, then
Live, History, People, Settings). THEN run verification (flutter analyze + build/
run) and report REAL output, fixing errors before finishing.
```

---

## Before you paste — what to expect
- **Flutter install takes a while** (SDK + Android SDK/Android Studio, ~10GB, up to
  ~1–2 hrs). The agent automates what it can and will hand you a short checklist for
  anything that needs the GUI (e.g. Android Studio first-run, a device/emulator).
- **Test on your phone over Wi-Fi**: enable USB debugging (or `adb` over Wi-Fi),
  set the app's server URL to your laptop's `hostname -I` address, keep both on the
  same network. Or use `flutter run -d chrome` for a quick desktop check first.
- **The Android cleartext-HTTP fix is essential** — without it the app silently
  can't reach `http://192.168.x.x:8000`. The prompt handles it; just know that's
  why it's there.

## On the skills/MCP
- `ui-ux-pro-max` skill → used for genuine UX/design decisions (great fit).
- 21st.dev Magic MCP → **emits React, not Flutter**, so the prompt uses it for
  *visual inspiration only* and implements native Flutter. That's the honest way to
  use it here; don't expect it to output runnable Flutter.

## After it's done, send me a report with:
1. `flutter --version` + `flutter doctor` summary (and any manual steps you had to
   finish).
2. Which target you verified on (physical Android / emulator / chrome) + that
   `flutter analyze` is clean and it builds.
3. A live WebSocket alert firing (Deaf flash/vibrate + Blind Kokoro audio) + the
   multi-person render.
4. Enrollment (multi-photo) + live view + history detail working.
5. Accessibility proof (Semantics, big targets, text scaling, reduce-motion
   degrade) + backend/PWA non-regression.

This gives you the native, animated, accessibility-first app — the "wow" build for
the panel — while the ESP32 is still in transit, all over the same backend you've
already hardened.
