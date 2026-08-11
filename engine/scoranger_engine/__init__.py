"""Scoranger engine. Loads repo-root .env (API keys) into the environment."""

import os as _os
from pathlib import Path as _Path


def _load_dotenv() -> None:
    env_file = _Path(__file__).resolve().parents[2] / ".env"
    if not env_file.is_file():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            _os.environ.setdefault(key.strip(), value.strip())


_load_dotenv()
