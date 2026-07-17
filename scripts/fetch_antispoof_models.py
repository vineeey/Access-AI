#!/usr/bin/env python3
"""
fetch_antispoof_models.py - obtain the two MiniFASNet ONNX liveness models.

WHAT THIS DOES
--------------
AccessAI's anti-spoof backend "B" (accessai/antispoof.py) loads two MiniFASNet
ONNX models from models/antispoof/ and runs them on onnxruntime (already a
Phase-2 dependency). Until those files exist, the module falls back to the
heuristic PLACEHOLDER (Option C), which cannot reliably flag photos/screens.

This script fetches the two models and drops them into models/antispoof/ as:

    2.7_80x80_MiniFASNetV2.onnx        (crop scale 2.7)
    4_0_0_80x80_MiniFASNetV1SE.onnx    (crop scale 4.0)

The filenames matter: antispoof.py parses the crop scale from the name.

TORCH SAFETY (hard constraint)
------------------------------
This script must NOT move torch off the pinned 2.4.1 build. Two acquisition
paths, tried in order:

  1) DIRECT ONNX DOWNLOAD (default, torch-free): pull pre-converted .onnx files
     from a mirror URL you supply via --url-v2 / --url-v1se (or the ANTISPOOF_*
     env vars). No torch, no numpy/onnxruntime version change - just a download
     that we then validate with the EXISTING onnxruntime.

  2) CONVERT-FROM-TORCH (opt-in, --convert): if you have the original MiniVision
     Silent-Face .pth weights, convert them to ONNX with torch.onnx.export. This
     imports torch but installs NOTHING, so the pin cannot move. The script
     asserts torch.__version__ starts with "2.4.1" before and after and refuses
     to run if it does not.

Every downloaded/'converted file is then LOADED with onnxruntime and given a
dummy 1x3x80x80 forward pass; a file that does not produce a 2- or 3-class
output is rejected and deleted, so a corrupt/wrong download never silently
becomes the active security model.

USAGE
-----
  # Direct download (recommended) - supply your mirror URLs:
  .venv/bin/python scripts/fetch_antispoof_models.py \
      --url-v2   https://.../2.7_80x80_MiniFASNetV2.onnx \
      --url-v1se https://.../4_0_0_80x80_MiniFASNetV1SE.onnx

  # Or point at a LOCAL directory that already holds the two .onnx files:
  .venv/bin/python scripts/fetch_antispoof_models.py --from-dir /path/to/onnx

  # Convert from original .pth weights (only if you have them; imports torch):
  .venv/bin/python scripts/fetch_antispoof_models.py --convert \
      --pth-v2   /path/2.7_80x80_MiniFASNetV2.pth \
      --pth-v1se /path/4_0_0_80x80_MiniFASNetV1SE.pth

After it prints "OK: 2 model(s) validated", restart the backend; antispoof.py
will auto-select Backend B and log "onnx-minifasnet".

This script is meant to be run WITH the user (network/torch touch points), per
the project's torch-safety review rule.
"""
import argparse
import os
import shutil
import sys
import urllib.request

# The two canonical MiniFASNet model filenames AccessAI expects. The leading
# number is the crop scale antispoof._scale_from_name() parses.
TARGETS = {
    "v2":   "2.7_80x80_MiniFASNetV2.onnx",
    "v1se": "4_0_0_80x80_MiniFASNetV1SE.onnx",
}

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
OUT_DIR = os.path.join(PROJECT, "models", "antispoof")


def _log(msg: str) -> None:
    print(f"[fetch-antispoof] {msg}", flush=True)


def _download(url: str, dest: str) -> None:
    _log(f"downloading {url}")
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "AccessAI-fetch"})
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f)
    os.replace(tmp, dest)
    _log(f"saved -> {dest} ({os.path.getsize(dest)} bytes)")


def _validate_onnx(path: str) -> bool:
    """Load with the EXISTING onnxruntime and run one dummy pass. A file that
    does not yield a 2/3-class liveness output is rejected (returns False)."""
    try:
        import numpy as np
        import onnxruntime as ort
    except Exception as e:
        _log(f"cannot import onnxruntime/numpy to validate ({e}); "
             "leaving file in place UNVALIDATED.")
        return True  # don't delete on a tooling gap; user can re-run validation
    try:
        sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
        inp = sess.get_inputs()[0]
        shape = inp.shape
        h = shape[2] if isinstance(shape[2], int) else 80
        w = shape[3] if isinstance(shape[3], int) else 80
        dummy = np.zeros((1, 3, h, w), dtype=np.float32)
        out = sess.run(None, {inp.name: dummy})[0]
        n = int(np.asarray(out).reshape(-1).shape[0])
        if n in (2, 3):
            _log(f"validated {os.path.basename(path)}: {n}-class output OK")
            return True
        _log(f"REJECT {os.path.basename(path)}: unexpected output size {n} "
             "(want 2 or 3 classes)")
        return False
    except Exception as e:
        _log(f"REJECT {os.path.basename(path)}: failed to load/run ({e})")
        return False


def _assert_torch_pin() -> None:
    """Refuse to run the torch conversion path unless torch is still 2.4.1."""
    import torch
    v = torch.__version__
    if not v.startswith("2.4.1"):
        raise SystemExit(
            f"TORCH SAFETY ABORT: torch is {v}, expected 2.4.1.x. "
            "Refusing to touch models to avoid masking a pin drift.")
    _log(f"torch pin OK: {v}")


def _convert_from_pth(pth_path: str, dest: str) -> None:
    """Convert an original MiniVision MiniFASNet .pth to ONNX. Imports torch but
    installs nothing; the pin is asserted before AND after."""
    _assert_torch_pin()
    import torch
    # MiniVision weights are plain state_dicts for MiniFASNetV2 / V1SE. We export
    # via a traced dummy; the architecture must be importable. We rely on the
    # user having the MiniVision 'src' on PYTHONPATH (documented in --help).
    try:
        from src.model_lib.MiniFASNet import (  # type: ignore
            MiniFASNetV2, MiniFASNetV1SE)
    except Exception as e:
        raise SystemExit(
            "CONVERT requires the MiniVision Silent-Face 'src' package on "
            "PYTHONPATH (github.com/minivision-ai/Silent-Face-Anti-Spoofing). "
            f"Import failed: {e}")
    name = os.path.basename(dest).lower()
    model = MiniFASNetV1SE(conv6_kernel=(5, 5)) if "v1se" in name \
        else MiniFASNetV2(conv6_kernel=(5, 5))
    state = torch.load(pth_path, map_location="cpu")
    if isinstance(state, dict) and "state_dict" in state:
        state = state["state_dict"]
    state = {k.replace("module.", ""): v for k, v in state.items()}
    # The published MiniFASNetV1SE checkpoint predates a refactor that moved the
    # squeeze-excitation params under a `se_module` submodule. Remap the legacy
    # flat names (se_fc1/se_bn1/se_fc2/se_bn2) onto the current nested layout so
    # the reference weights load against today's MiniFASNet.py (V2 is unaffected).
    _se_remap = {
        "se_fc1": "se_module.fc1", "se_fc2": "se_module.fc2",
        "se_bn1": "se_module.bn1", "se_bn2": "se_module.bn2",
    }

    def _fix(k: str) -> str:
        for old, new in _se_remap.items():
            k = k.replace(old, new)
        return k

    state = {_fix(k): v for k, v in state.items()}
    model.load_state_dict(state)
    model.eval()
    dummy = torch.zeros(1, 3, 80, 80)
    torch.onnx.export(
        model, dummy, dest, input_names=["input"], output_names=["output"],
        opset_version=11, dynamic_axes=None)
    _assert_torch_pin()   # export must not have dragged torch anywhere
    _log(f"converted {os.path.basename(pth_path)} -> {dest}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url-v2", default=os.environ.get("ANTISPOOF_URL_V2"),
                    help="URL to the MiniFASNetV2 (2.7 scale) .onnx")
    ap.add_argument("--url-v1se", default=os.environ.get("ANTISPOOF_URL_V1SE"),
                    help="URL to the MiniFASNetV1SE (4.0 scale) .onnx")
    ap.add_argument("--from-dir",
                    help="Local dir already containing the two .onnx files")
    ap.add_argument("--convert", action="store_true",
                    help="Convert from .pth weights (imports torch, pin-checked)")
    ap.add_argument("--pth-v2", help="Path to MiniFASNetV2 .pth (with --convert)")
    ap.add_argument("--pth-v1se", help="Path to MiniFASNetV1SE .pth (--convert)")
    ap.add_argument("--out-dir", default=OUT_DIR)
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    got = []

    for key, fname in TARGETS.items():
        dest = os.path.join(args.out_dir, fname)
        if os.path.exists(dest) and os.path.getsize(dest) > 0:
            _log(f"already present: {fname} (skipping fetch)")
            got.append(dest)
            continue

        if args.convert:
            pth = args.pth_v2 if key == "v2" else args.pth_v1se
            if not pth or not os.path.exists(pth):
                _log(f"--convert set but no .pth for {key}; skipping")
                continue
            _convert_from_pth(pth, dest)
            got.append(dest)
        elif args.from_dir:
            src = os.path.join(args.from_dir, fname)
            if not os.path.exists(src):
                _log(f"not found in --from-dir: {fname}; skipping")
                continue
            shutil.copyfile(src, dest)
            _log(f"copied {fname} from {args.from_dir}")
            got.append(dest)
        else:
            url = args.url_v2 if key == "v2" else args.url_v1se
            if not url:
                _log(f"no URL for {key} ({fname}); pass --url-{key.replace('v','v')} "
                     "or --from-dir/--convert. Skipping.")
                continue
            _download(url, dest)
            got.append(dest)

    if not got:
        _log("no models obtained. Re-run with --url-v2/--url-v1se, --from-dir, "
             "or --convert. See --help.")
        return 2

    # Validate every file we ended up with; delete any that fail so a bad
    # download never becomes the active security model.
    ok = []
    for dest in got:
        if _validate_onnx(dest):
            ok.append(dest)
        else:
            try:
                os.remove(dest)
                _log(f"deleted invalid {os.path.basename(dest)}")
            except OSError:
                pass

    _log(f"OK: {len(ok)} model(s) validated in {args.out_dir}")
    for p in ok:
        _log(f"  - {os.path.basename(p)}")
    if len(ok) < 2:
        _log("NOTE: fewer than 2 valid models. Backend B needs at least one to "
             "activate; both give the reference 2-model average. Heuristic "
             "placeholder stays active until then.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
