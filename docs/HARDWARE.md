# AccessAI — Hardware Readiness (ESP32-CAM)

**Status: documented + software-ready. No hardware is required to run AccessAI,
and none was used to build this.** This file is the bring-up guide for when you
add a real camera-at-the-door. The software side is already done:

- The app opens a camera in **exactly one place** (`accessai/camera.py`), which
  accepts either a webcam index *or* an MJPEG URL string.
- Switching from a laptop webcam to an ESP32-CAM is a **one-line change** in
  `config.py`.
- The camera thread (`run.py::camera_loop`) already **reconnects with backoff**
  (reopens the source and retries every 2 s) if the stream drops — exactly what
  a Wi-Fi camera needs.
- A **doorbell webhook** already exists: `POST /ring` (optionally with a posted
  JPEG). A physical button wired to the ESP32 can drive the real pipeline.

---

## The one-line swap

`accessai/camera.py` wraps `cv2.VideoCapture`, which takes an int index or a URL.
So all you change is the source in `config.py`:

```python
# Before (development — laptop webcam)
CAMERA_SOURCE = 0

# After (deployment — ESP32-CAM MJPEG stream)
CAMERA_SOURCE = "http://192.168.1.50:81/stream"
```

Nothing else in the codebase changes. Frames flow through the same pipeline,
snapshots, DB, and dashboard.

---

## Two supported boards

| | **ESP32-S3-Sense (Seeed XIAO)** — recommended | **AI-Thinker ESP32-CAM** — budget |
|---|---|---|
| Camera | OV2640 (bundled) | OV2640 (bundled) |
| PSRAM | 8 MB | 4 MB (varies by clone) |
| Mic | **On-board PDM mic** (useful for future on-device audio) | none |
| USB | USB-C, native — flash directly | **needs an external USB-TTL adapter** |
| Programming | Easy (no jumper dance) | Must ground **GPIO0** to flash, then remove |
| Antenna | On-board (decent) | On-board or u.FL |
| Price | ~$14 | ~$6–9 |
| Pick it when… | you want a clean bring-up + a mic path | you want the cheapest possible node |

Both expose the standard Espressif `CameraWebServer` MJPEG stream at
`http://<device-ip>:81/stream`, which is what `CAMERA_SOURCE` points at.

---

## Bill of materials (minimal doorbell node)

| # | Part | Notes |
|---|------|-------|
| 1 | ESP32-S3-Sense **or** AI-Thinker ESP32-CAM | see table above |
| 1 | 5 V / ≥2 A power supply (USB or screw-terminal) | camera + Wi-Fi is current-hungry; brownouts cause reboots |
| 1 | Momentary push button (the "doorbell") | wired button → GPIO → `POST /ring` |
| 1 | 10 kΩ resistor | pull-up/down for the button (or use `INPUT_PULLUP`) |
| 1 | USB-TTL serial adapter (CP2102/FTDI) | **AI-Thinker only** — for flashing |
| — | Dupont wires, a weatherproof enclosure | outdoor mounting |
| — | (optional) small 5 V speaker + amp | only if you later move TTS on-device; today TTS runs on the host |

---

## Wiring

### Power (both boards)
```
5V supply (+) ──► 5V pin
5V supply (−) ──► GND
```
Use a supply that can hold **2 A**. A thin USB cable or a weak supply is the #1
cause of ESP32-CAM boot loops.

### Doorbell button → GPIO (drives POST /ring)
```
             ┌────────────┐
   3V3 ──────┤            │
             │   button   │
   GPIO(in)──┤ (momentary)│
             └─────┬──────┘
                   │
               10kΩ to GND   (or use pinMode(pin, INPUT_PULLUP) and wire to GND)
```
Use a free GPIO (e.g. **GPIO13** on AI-Thinker, any free pad on the S3). On
press, the sketch sends `POST /ring` to the AccessAI host.

### Flashing the AI-Thinker (only)
```
USB-TTL 5V ──► 5V        USB-TTL TX ──► U0R (RX)
USB-TTL GND──► GND       USB-TTL RX ──► U0T (TX)
GPIO0 ──► GND   (ONLY while flashing; remove afterward and reset)
```
The S3-Sense flashes over its native USB-C — no adapter, no GPIO0 jumper.

---

## Firmware outline (Arduino / ESP-IDF)

**This is an outline, not a drop-in sketch.** Start from Espressif's stock
**`CameraWebServer`** example (Arduino IDE → Examples → ESP32 → Camera →
CameraWebServer), which already serves the `:81/stream` MJPEG endpoint AccessAI
consumes. Then add a doorbell button that calls `POST /ring`.

```cpp
// ---- outline only; fill board pins + credentials ----
#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPClient.h>

const char* WIFI_SSID = "...";
const char* WIFI_PASS = "...";
const char* ACCESSAI  = "http://192.168.1.10:8000";  // the host running run.py
const int   BUTTON_PIN = 13;

void setup() {
  // 1) Select your board's camera pin map (CAMERA_MODEL_AI_THINKER or
  //    CAMERA_MODEL_XIAO_ESP32S3), then esp_camera_init(&config) — copy this
  //    verbatim from the CameraWebServer example.
  // 2) WiFi.begin(WIFI_SSID, WIFI_PASS); wait for WL_CONNECTED; print IP.
  // 3) startCameraServer();          // gives you http://<ip>:81/stream
  // 4) pinMode(BUTTON_PIN, INPUT_PULLUP);
}

void loop() {
  static bool prev = HIGH;
  bool now = digitalRead(BUTTON_PIN);
  if (prev == HIGH && now == LOW) {          // falling edge = press
    ringDoorbell();                          // debounce in real firmware
    delay(200);
  }
  prev = now;
}

void ringDoorbell() {
  // Simplest: let the host grab the current frame.
  HTTPClient http;
  http.begin(String(ACCESSAI) + "/ring");
  int code = http.POST("");                  // empty body → host uses latest frame
  http.end();

  // Optional: post the device's OWN JPEG so the host doesn't pull the stream:
  //   camera_fb_t* fb = esp_camera_fb_get();
  //   http.addHeader("Content-Type", "image/jpeg");
  //   http.POST(fb->buf, fb->len);          // host decodes it (frame_source: posted-jpeg)
  //   esp_camera_fb_return(fb);
}
```

`POST /ring` accepts **either** an empty body (the host uses the latest streamed
frame) **or** a raw JPEG body (the device's own capture). The response reports
which was used:

```json
{ "ok": true, "frame_source": "posted-jpeg", "event": { ... } }
```
`frame_source` is one of `posted-jpeg`, `latest-frame`, or `blank`.

---

## Bring-up checklist

1. Flash the CameraWebServer example; open the ESP32's own web UI and confirm a
   picture. Note its IP.
2. In a browser on the same network, open `http://<esp32-ip>:81/stream` — you
   should see MJPEG.
3. Set `CAMERA_SOURCE = "http://<esp32-ip>:81/stream"` in `config.py`; run
   `python3 run.py`. The AccessAI **Live View** now shows the door camera. If
   Wi-Fi hiccups, the camera thread reconnects automatically (2 s backoff).
4. Add the button + `ringDoorbell()`; press it and watch a real event appear in
   **Visitor History** and the dashboard, spoken/shown per the current mode.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Board reboots / "brownout detector" | Underpowered supply or thin cable — use ≥2 A, short cable. |
| Stream opens then freezes | Weak Wi-Fi. Move closer / add antenna; the host will auto-reconnect. |
| `Could not open camera source '…'` at startup | ESP32 not powered/reachable, or wrong IP/port. The message comes from `accessai/camera.py`. |
| Flashing fails (AI-Thinker) | GPIO0 not grounded during flash, or TX/RX swapped. |
| Laggy stream | Lower the JPEG frame size / quality in the CameraWebServer config. |
