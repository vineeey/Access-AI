# Mobile Background Push (FCM) — the later path

**Status: documented, NOT implemented.** The Phase-14 PWA delivers **live** alerts
over a WebSocket while the app is open. Waking the phone when the app is **closed**
requires a push service (FCM). This file is the recipe for that upgrade; no
Firebase dependency is added now.

## Why it isn't on yet

Web push (and FCM) require a **secure context (HTTPS)**. Over plain
`http://192.168.x.x` the browser will not register a push subscription or a
background service worker reliably. So background push is gated on serving the app
over HTTPS first.

## Prerequisites (do these first)

1. **Serve over HTTPS.** The zero-config option is a Cloudflare tunnel:
   ```bash
   cloudflared tunnel --url http://localhost:8000
   ```
   This gives a public `https://<random>.trycloudflare.com` URL. Open
   `https://<random>.trycloudflare.com/app` on the phone → the existing service
   worker now registers (secure context) and the app is installable to the home
   screen. Everything already built keeps working; only install + push were gated.
2. A **Firebase project** (free tier) with Cloud Messaging enabled, and the Web
   app config (`apiKey`, `messagingSenderId`, `appId`, and a Web Push **VAPID** key).

## Client changes (later)

1. Add `web/app/firebase-messaging-sw.js` (a SECOND, dedicated service worker that
   Firebase controls) that imports the Firebase compat SDK and calls
   `firebase.initializeApp(...)` + `messaging.onBackgroundMessage(...)` to show a
   notification when the app is closed.
2. In `app.js`, after the existing SW registration, request notification
   permission and call `getToken(messaging, { vapidKey })`. POST the returned
   device token to the backend `/register_push` route.

## Server changes (later)

1. **`POST /register_push`** — store `{token, mode}` in the DB (a new `push_tokens`
   table, additive). A trivial no-op stub can land first (accept + persist the
   token) without any Firebase dependency — that is the only server change safe to
   add now, and it is intentionally left out until HTTPS is in place so we don't
   ship a dead route.
2. On a doorbell **event** (in `broadcast()` or right after `pipeline.run_once`),
   additionally POST to the FCM HTTP v1 endpoint for every stored token:
   ```
   POST https://fcm.googleapis.com/v1/projects/<project-id>/messages:send
   Authorization: Bearer <OAuth2 access token from the service-account JSON>
   { "message": { "token": "<device token>",
       "notification": { "title": "Someone's at the door",
                          "body": "<announcement_text>" },
       "webpush": { "fcm_options": { "link": "/app" } } } }
   ```
   Gate this behind a config flag (e.g. `ENABLE_PUSH`) so it is off by default and
   never blocks the doorbell if FCM is slow or unreachable (fire-and-forget, in the
   same executor pattern the rest of the server uses).

## Scope guard

- No Firebase packages are added to `requirements.txt` now.
- The current WebSocket alert path is unchanged and remains the primary channel
  while the app is open. FCM is strictly additive for the app-closed case.
- Torch pins and the ML stack are untouched by this path (it is pure HTTP).
