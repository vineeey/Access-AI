# AccessAI — Mobile App Readiness (Flutter)

**Status: specification only. No Flutter code is included, and none is required
to run AccessAI.** The backend is already a clean HTTP + WebSocket API, so a
mobile app is purely a *client* — it adds no server-side work. This document
specifies exactly how a Flutter app maps onto the **existing** endpoints so a
mobile developer can build it without touching the Python.

The mobile app is where the accessibility payoff lands: a blind user's phone
speaks announcements and takes voice commands anywhere in the house; a deaf
user's phone **vibrates + flashes + shows big text** the instant someone rings.

---

## Why the API is already mobile-ready

- **Everything is HTTP/JSON** over one FastAPI server (default `:8000`).
- **Live push** is a single WebSocket (`/events`) that broadcasts both visitor
  events and voice-command results — no polling needed.
- **The live camera** is plain **MJPEG** (`/video`), which Flutter renders with
  an `Image.network` / `Mjpeg` widget.
- **Voice commands** already accept an **uploaded WAV** (`POST /listen`), so the
  phone records audio and the server does the Whisper transcription — no ML on
  the phone.
- The server already emits a **central health** snapshot (`GET /status`) the app
  can show as a status screen.

No new endpoints are needed for a first-class app.

---

## Endpoint → screen map

| Flutter screen / action | Endpoint | Notes |
|---|---|---|
| **Live view** | `GET /video` | MJPEG stream widget |
| **Ring / trigger analysis** | `POST /trigger` (or `POST /ring`) | returns the event JSON |
| **Live event push** | `WS /events` | `{type:"event", event:{…}}` and `{type:"voice", …}` |
| **History list** | `GET /history` | array of event dicts |
| **Event detail** | `GET /event/{id}` | one event |
| **Snapshot image** | `GET /snapshot/{id}` | JPEG |
| **Speak a command (push-to-talk)** | `POST /listen` (multipart WAV) | server transcribes + acts + speaks; returns `{command, intent, answer, spoke}` |
| **Toggle always-listening** | `POST /wakeword/on` \| `/wakeword/off` | opt-in |
| **Wake status pill** | `GET /wakeword_status` | |
| **Mode switch (Blind/Deaf/Both)** | `POST /mode` | |
| **Language switch** | `POST /user_language` | 11 languages |
| **Reply to visitor (Deaf two-way)** | `POST /reply` | text → spoken at the door |
| **Enroll a face** | `POST /enroll` | |
| **Frequent-visitor suggestions** | `GET /suggestions`, `POST /suggestions/{confirm\|dismiss}` | auto-enroll |
| **System health screen** | `GET /status` | per-module state + flags + torch version |

---

## The event payload (what the app renders)

Events arrive over `/events` and from `/history`. The app should read these
fields (all already on the `VisitorEvent`):

```jsonc
{
  "type": "event",
  "event": {
    "event_id": "…",
    "timestamp": "2026-07-10T12:00:00",
    "identity": { "known": true, "name": "Rahul", "confidence": 0.72 },
    "is_spoof": false,
    "visitor_count": 1,
    "carried_objects": ["a package"],
    "scene_summary": "A person in a blue uniform holding a box.",
    "ocr_text": "FEDEX 4821",
    "speech_transcript": "package for you",
    "translated_transcript": "package for you",
    "language_detected": "en",
    "reid_id": "v_1a2b3c4d",
    "reid_seen_count": 3,
    "intent": "likely delivery",
    "announcement_text": "Rahul is at the door. Carrying a package. Likely a delivery. They said: \"package for you\".",
    "snapshot_path": "…"
  }
}
```

**`announcement_text` is the one field the UI must always surface** — it is the
final, mode-appropriate sentence the system composed. Everything else is for
richer display (badges, chips, the snapshot).

Voice-command results arrive as:
```jsonc
{ "type": "voice", "command": "who is at the door",
  "intent": "who_is_there", "answer": "Rahul is at the door…", "spoke": true }
```

---

## Accessibility behaviour the app must implement

This is the point of the app — mirror what the web dashboard does, using native
phone capabilities:

- **Blind Mode**
  - Speak `announcement_text` with the phone's TTS (`flutter_tts`) on every
    incoming event. (The server also speaks on the host; the app gives the user
    audio *on their person*.)
  - Offer push-to-talk: record a few seconds of audio, `POST /listen` as a WAV,
    speak the returned `answer`. Optionally wire the phone's own wake word or a
    persistent notification action to start recording.
- **Deaf Mode**
  - On each event: **vibrate** (`HapticFeedback` / `vibration` package), **flash
    the screen / torch**, and show `announcement_text` in **large, high-contrast
    text**. Never rely on sound.
  - Provide the reply box → `POST /reply` (text is spoken at the door).
- **Both**: do both.

The app should honour the server's current mode from `GET /mode` and let the
user change it via `POST /mode`.

---

## Connectivity & config

- The app needs the **host base URL** (e.g. `http://192.168.1.10:8000`) — a
  simple settings field. On the same LAN this is direct; for remote access the
  user puts the host behind a reverse proxy / VPN (out of scope here).
- Use a WebSocket auto-reconnect (exponential backoff) for `/events`, mirroring
  how the web dashboard reconnects.
- All endpoints already return **clean JSON on error** (never a stack trace), so
  the app can surface a friendly message on any non-200.

---

## Suggested build order

1. **Settings + health** — enter host URL; show `GET /status` so the user can
   confirm the backend is reachable and see which modules are live.
2. **Live view + Ring** — MJPEG widget + `POST /ring`, render the returned event.
3. **Event push + accessibility** — connect `/events`; implement Blind (TTS) and
   Deaf (vibrate/flash/big-text) rendering of `announcement_text`.
4. **History** — `GET /history` + `GET /snapshot/{id}`.
5. **Voice commands** — record → `POST /listen` → speak `answer`; toggle
   always-listening.
6. **Two-way + enroll + suggestions** — `POST /reply`, `POST /enroll`,
   `/suggestions`.

No Python changes are required for any of the above. If the app later wants
server-sent push notifications while backgrounded (FCM/APNs), that would be the
one backend addition worth making — everything else is already exposed.
