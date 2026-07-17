"""
TranslateModule - multi-language translation of the visitor's speech (Phase 8).

The visitor (from Phase-7 Whisper) may speak Hindi, Malayalam, Tamil, etc., while
the blind/deaf user consumes a single chosen language (config.USER_LANGUAGE). This
module translates visitor -> user so the announcement is spoken (Blind) and
captioned (Deaf) in a language the user actually understands. The result lands in
ev.translated_transcript, which accessibility.compose_announcement already prefers
over the raw transcript.

Backends (priority, all behind the same interface):
  A "github"  - PREFERRED, torch-safe. Reuses the Phase-6 VLMModule's
                OpenAI-compatible chat endpoint + multi-key FAILOVER for a
                text-only translation call. No new dependency, never moves torch.
  B "local"   - an offline MT model (e.g. NLLB / IndicTrans2). HEAVY and risks
                pulling torch; lazy-loaded and only used if explicitly selected.
  C "none"    - passthrough: translate() returns the original text unchanged.

Design rules (same as every AccessAI module):
  * NEVER raise from __init__ or translate() - degrade to passthrough on anything
    missing (no keys, no model, dead network) so the doorbell never breaks.
  * Same-language (src == target) => return the original with NO API call (saves
    the free-tier quota; also covers English->English).
  * translate() ALWAYS returns a string.
"""


# A small, sensible default so the module is usable standalone (run.py passes the
# full config.LANGUAGE_NAMES in). Maps ISO code -> human name for the prompt.
_DEFAULT_LANGUAGE_NAMES = {
    "en": "English", "hi": "Hindi", "ml": "Malayalam", "ta": "Tamil",
    "te": "Telugu", "kn": "Kannada", "bn": "Bengali", "mr": "Marathi",
    "gu": "Gujarati", "pa": "Punjabi", "ur": "Urdu",
}


class TranslateModule:
    def __init__(self, backend="github", user_language="en",
                 language_names=None, vlm=None):
        self.backend = (backend or "none").lower()
        self.user_language = (user_language or "en").strip() or "en"
        self.language_names = dict(language_names or _DEFAULT_LANGUAGE_NAMES)
        self.vlm = vlm                      # Phase-6 VLMModule (reused for "github")
        self._local = None                  # lazy-loaded MT model for "local"
        self._local_failed = False

        if self.backend == "github":
            ok = bool(vlm is not None and vlm.available())
            why = "reusing Phase-6 GitHub Models keys" if ok else (
                "no VLM keys available - PASSTHROUGH (shows original)")
            print(f"[TranslateModule] backend=github, target="
                  f"{self.lang_name(self.user_language)} | {why}")
        elif self.backend == "local":
            print(f"[TranslateModule] backend=local (offline MT), target="
                  f"{self.lang_name(self.user_language)} | model lazy-loads on "
                  f"first use (torch-safety rules apply)")
        else:
            self.backend = "none"
            print(f"[TranslateModule] backend=none | PASSTHROUGH: translation "
                  f"disabled, original transcript shown unchanged")

    # ------------------------------------------------------------------ status
    def available(self) -> bool:
        """True when the backend can ACTUALLY translate. 'none' is a passthrough,
        so it's not 'available' even though translate() still works (returns the
        original) - lets the UI say 'showing original'."""
        if self.backend == "github":
            return bool(self.vlm is not None and self.vlm.available())
        if self.backend == "local":
            return not self._local_failed and self._ensure_local()
        return False

    def backend_name(self) -> str:
        return self.backend

    def lang_name(self, code) -> str:
        """Human-readable name for an ISO code (falls back to the code itself)."""
        code = (code or "").strip()
        return self.language_names.get(code, code or "the target language")

    def set_user_language(self, code) -> str:
        code = (code or "").strip()
        if code:
            self.user_language = code
        return self.user_language

    def status(self) -> dict:
        return {
            "backend": self.backend,
            "available": self.available(),
            "user_language": self.user_language,
            "user_language_name": self.lang_name(self.user_language),
        }

    # --------------------------------------------------------------- translate
    def translate(self, text, src_lang="", target_lang=None) -> str:
        """Translate `text` from src_lang into target_lang (default user_language).

        Returns a STRING always. Empty in -> empty out. Same-language or any
        failure -> the original text unchanged. Never raises.
        """
        text = (text or "").strip()
        if not text:
            return ""
        target = (target_lang or self.user_language or "en").strip()
        src = (src_lang or "").strip()

        # Same language => no API call (quota-saving; covers en->en).
        if src and src == target:
            return text

        try:
            if self.backend == "github":
                out = ""
                if self.vlm is not None and self.vlm.available():
                    out = self.vlm.translate_text(text, self.lang_name(target))
                return out.strip() if out and out.strip() else text
            if self.backend == "local":
                return self._translate_local(text, src, target) or text
            # backend "none" -> passthrough
            return text
        except Exception as e:                                # pragma: no cover
            print(f"[TranslateModule] translate failed ({e}); using original.")
            return text

    # ------------------------------------------------------- local MT (Option B)
    def _ensure_local(self) -> bool:
        """Lazy-load an offline MT model. Returns True if usable. Kept minimal and
        OFF by default because it risks moving torch (see the torch-safety rules).
        """
        if self._local is not None:
            return True
        if self._local_failed:
            return False
        try:
            # Intentionally not imported at module top so selecting "github"/"none"
            # never drags transformers/torch into the process.
            from transformers import pipeline as hf_pipeline  # noqa: F401
            # A concrete model would be wired here (e.g. NLLB-200-distilled-600M).
            # Left unloaded by default to honour the torch-safety guardrail; flip
            # to a real load only after pinning torch and re-checking YOLO.
            self._local_failed = True
            print("[TranslateModule] local backend selected but no offline model "
                  "is wired (torch-safety); PASSTHROUGH until one is configured.")
            return False
        except Exception as e:
            self._local_failed = True
            print(f"[TranslateModule] local MT unavailable ({e}); PASSTHROUGH.")
            return False

    def _translate_local(self, text, src, target) -> str:
        if not self._ensure_local():
            return ""
        return ""   # pragma: no cover - real model call would go here
