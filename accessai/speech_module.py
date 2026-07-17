"""
SpeechModule - offline speech recognition (Phase 7).

On a doorbell press we can capture a few seconds of microphone audio, gate it
with Voice Activity Detection (so we never transcribe silence), and transcribe
it OFFLINE with Whisper on the CPU. The result -> ev.speech_transcript +
ev.language_detected, which the accessibility layer already turns into the
' They said: "..."' tail (Blind) and the Deaf-mode caption.

Three independent capabilities, each guarded so a missing piece only disables
that piece (mirrors every AccessAI module - never raise from __init__):

    whisper  - transcription (the CORE; available() == this)
    mic      - sounddevice/PortAudio live capture (optional; /transcribe upload
               still works without it)
    silero   - neural VAD (optional; falls back to an energy/RMS gate)

Key design choices (from the phase spec):
  * Feed Whisper a 16 kHz MONO float32 numpy array, NOT a file path -> no ffmpeg
    dependency at runtime, and fp16=False for CPU.
  * LAZY-load the Whisper model on first use so importing/booting the server
    never blocks on the one-time model download.
  * VAD matters: Whisper will HALLUCINATE words from noise/silence, so we drop
    clips with less than SPEECH_VAD_MIN_SPEECH_SEC of real speech.
"""

import wave

import numpy as np

try:
    import sounddevice as sd
    _HAS_MIC_LIB = True
except Exception as e:                                   # pragma: no cover
    _HAS_MIC_LIB = False
    print(f"[SpeechModule] sounddevice unavailable, live mic disabled: {e}")

try:
    import whisper
    _HAS_WHISPER = True
except Exception as e:                                   # pragma: no cover
    _HAS_WHISPER = False
    print(f"[SpeechModule] openai-whisper unavailable, transcription disabled: {e}")

try:
    from silero_vad import load_silero_vad, get_speech_timestamps
    _HAS_SILERO = True
except Exception as e:                                   # pragma: no cover
    _HAS_SILERO = False
    # Not noisy: the energy fallback covers this. Logged once in __init__.


class SpeechModule:
    def __init__(self, model_name="base", sample_rate=16000, seconds=5,
                 use_vad=True, vad_min_speech_sec=0.3, language=None):
        self.model_name = model_name
        self.sample_rate = int(sample_rate)
        self.seconds = int(seconds)
        self.use_vad = bool(use_vad)
        self.vad_min_speech_sec = float(vad_min_speech_sec)
        # Whisper wants None (auto-detect) or a language code; "" -> None.
        self.language = language or None

        self._has_mic_lib = _HAS_MIC_LIB
        self._has_whisper = _HAS_WHISPER
        self._has_silero = _HAS_SILERO

        self._model = None            # Whisper, lazy-loaded in _ensure_model()
        self._silero_model = None
        self._warned_no_mic = False

        # Prepare Silero once (bundled with the pip package -> offline). On any
        # failure we simply fall back to the energy VAD; never raise.
        if self._has_silero:
            try:
                self._silero_model = load_silero_vad()
                print("[SpeechModule] Silero VAD ready.")
            except Exception as e:                        # pragma: no cover
                self._has_silero = False
                print(f"[SpeechModule] Silero load failed, using energy VAD: {e}")
        else:
            print("[SpeechModule] silero-vad not installed, using energy VAD.")

        core = "available" if self._has_whisper else "DISABLED (no whisper)"
        print(f"[SpeechModule] model={self.model_name}, {core} | "
              f"caps: whisper={self._has_whisper} mic={self._has_mic_lib} "
              f"silero={self._has_silero}")

    # ------------------------------------------------------------------ status
    def available(self) -> bool:
        # Transcription is the core capability; mic + VAD are enhancements.
        return self._has_whisper

    def capabilities(self) -> dict:
        return {"whisper": self._has_whisper, "mic": self._has_mic_lib,
                "silero": self._has_silero}

    def warm(self) -> None:
        """Load Whisper NOW instead of on the first transcription, so the first
        'Hear Visitor' answers in transcription-time only (not load+transcribe).
        Safe to call from a background thread at startup; never raises."""
        try:
            self._ensure_model()
        except Exception as e:                            # pragma: no cover
            print(f"[SpeechModule] warm-up failed (will retry on use): {e}")

    # ---------------------------------------------------------------- internal
    def _ensure_model(self):
        """Load Whisper on first use (one-time ~140MB download for 'base')."""
        if self._model is None and self._has_whisper:
            print(f"[SpeechModule] Loading Whisper '{self.model_name}' "
                  f"(first run downloads to ~/.cache/whisper)...")
            self._model = whisper.load_model(self.model_name)
            print("[SpeechModule] Whisper loaded.")
        return self._model

    @staticmethod
    def _as_mono_float32(audio) -> np.ndarray:
        """Coerce any array to a 1-D float32 numpy array in [-1, 1]."""
        a = np.asarray(audio)
        if a.ndim > 1:                       # (n, channels) -> mono
            a = a.mean(axis=1)
        a = a.astype(np.float32).reshape(-1)
        # Clamp defensively; recorded/decoded audio should already be in range.
        return np.clip(a, -1.0, 1.0)

    # ------------------------------------------------------------------ record
    def record(self, seconds=None):
        """Record `seconds` of 16 kHz mono float32 from the mic, or None.

        Never raises: no library, no device, or a PortAudio error all log once
        and return None (the pipeline then proceeds with an empty transcript).
        """
        if not self._has_mic_lib:
            if not self._warned_no_mic:
                print("[SpeechModule] No mic library; skipping live capture.")
                self._warned_no_mic = True
            return None
        secs = int(seconds or self.seconds)
        try:
            frames = int(secs * self.sample_rate)
            audio = sd.rec(frames, samplerate=self.sample_rate, channels=1,
                           dtype="float32")
            sd.wait()
            return self._as_mono_float32(audio)
        except Exception as e:                            # no device / PortAudio
            if not self._warned_no_mic:
                print(f"[SpeechModule] Mic capture failed ({e}); "
                      "continuing without audio.")
                self._warned_no_mic = True
            return None

    # --------------------------------------------------------------------- VAD
    def has_speech(self, audio) -> bool:
        """True if the clip contains at least vad_min_speech_sec of speech."""
        if audio is None:
            return False
        a = self._as_mono_float32(audio)
        if a.size == 0:
            return False

        if self._has_silero and self._silero_model is not None:
            try:
                import torch
                ts = get_speech_timestamps(
                    torch.from_numpy(a), self._silero_model,
                    sampling_rate=self.sample_rate, return_seconds=True)
                total = sum(seg["end"] - seg["start"] for seg in ts)
                return total >= self.vad_min_speech_sec
            except Exception as e:                        # pragma: no cover
                print(f"[SpeechModule] Silero VAD error, using energy gate: {e}")

        return self._energy_has_speech(a)

    def _energy_has_speech(self, a: np.ndarray) -> bool:
        """Fallback VAD: is there a contiguous voiced run >= the minimum?

        Split into 30 ms windows, compute per-window RMS, and mark windows above
        an ADAPTIVE threshold (a floor, plus a fraction of the clip's peak RMS)
        as voiced. Then require a run of consecutive voiced windows whose total
        duration reaches vad_min_speech_sec.
        """
        win = max(1, int(0.03 * self.sample_rate))       # 30 ms
        n_win = a.size // win
        if n_win == 0:
            return False
        windows = a[:n_win * win].reshape(n_win, win)
        rms = np.sqrt(np.mean(windows ** 2, axis=1) + 1e-12)
        peak = float(rms.max())
        # Silence floor OR 30% of the loudest window, whichever is higher.
        thresh = max(0.010, 0.30 * peak)
        voiced = rms >= thresh

        need = int(np.ceil(self.vad_min_speech_sec / 0.03))
        run = 0
        for v in voiced:
            run = run + 1 if v else 0
            if run >= need:
                return True
        return False

    # ------------------------------------------------------------- transcribe
    def transcribe(self, audio):
        """(text, language_code) from a numpy audio array. ("","") on any gap."""
        if audio is None or not self._has_whisper:
            return "", ""
        a = self._as_mono_float32(audio)
        if a.size == 0:
            return "", ""
        try:
            model = self._ensure_model()
            # fp16=False -> CPU. Passing a float32 array avoids ffmpeg.
            result = model.transcribe(a, language=self.language, fp16=False)
        except Exception as e:                            # pragma: no cover
            print(f"[SpeechModule] Whisper transcription failed: {e}")
            return "", ""
        return (result.get("text", "") or "").strip(), result.get("language", "") or ""

    def listen_and_transcribe(self, seconds=None):
        """Record from the mic, gate with VAD, transcribe. ("","") if nothing."""
        audio = self.record(seconds)
        if audio is None:
            return "", ""
        if self.use_vad and not self.has_speech(audio):
            print("[SpeechModule] No speech detected in clip; skipping Whisper.")
            return "", ""
        return self.transcribe(audio)

    # -------------------------------------------------------------- WAV upload
    def transcribe_wav(self, wav_bytes):
        """Decode WAV bytes -> 16 kHz mono float32 -> VAD + transcribe.

        Powers the manual /transcribe route so speech can be tested WITHOUT a
        mic. Uses stdlib `wave` (no extra dependency); resamples to 16 kHz with
        scipy if the WAV is at another rate, else a simple linear fallback.
        """
        if not self._has_whisper:
            return "", ""
        try:
            audio, rate = self._decode_wav(wav_bytes)
        except Exception as e:
            print(f"[SpeechModule] WAV decode failed: {e}")
            return "", ""
        if audio is None or audio.size == 0:
            return "", ""
        if rate != self.sample_rate:
            audio = self._resample(audio, rate, self.sample_rate)
        if self.use_vad and not self.has_speech(audio):
            print("[SpeechModule] Uploaded clip has no speech; skipping Whisper.")
            return "", ""
        return self.transcribe(audio)

    def _decode_wav(self, wav_bytes):
        """Return (mono float32 in [-1,1], sample_rate) from PCM WAV bytes."""
        import io
        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            n_channels = wf.getnchannels()
            sampwidth = wf.getsampwidth()
            rate = wf.getframerate()
            frames = wf.readframes(wf.getnframes())

        if sampwidth == 2:
            data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
        elif sampwidth == 4:
            data = np.frombuffer(frames, dtype=np.int32).astype(np.float32) / 2147483648.0
        elif sampwidth == 1:                              # 8-bit PCM is unsigned
            data = (np.frombuffer(frames, dtype=np.uint8).astype(np.float32)
                    - 128.0) / 128.0
        else:                                             # pragma: no cover
            raise ValueError(f"unsupported sample width {sampwidth}")

        if n_channels > 1:
            data = data.reshape(-1, n_channels).mean(axis=1)
        return self._as_mono_float32(data), rate

    @staticmethod
    def _resample(audio, src_rate, dst_rate):
        """Resample a 1-D float32 array from src_rate to dst_rate."""
        if src_rate == dst_rate or audio.size == 0:
            return audio
        n_out = int(round(audio.size * dst_rate / float(src_rate)))
        if n_out <= 0:
            return audio
        try:
            from scipy.signal import resample
            return resample(audio, n_out).astype(np.float32)
        except Exception:
            # Linear-interpolation fallback (no scipy).
            x_old = np.linspace(0.0, 1.0, num=audio.size, endpoint=False)
            x_new = np.linspace(0.0, 1.0, num=n_out, endpoint=False)
            return np.interp(x_new, x_old, audio).astype(np.float32)
