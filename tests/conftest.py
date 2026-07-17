"""Make the project root importable so `import accessai...` / `import config` work
under a plain `pytest -q` from anywhere."""

import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
