import json
import os
from functools import lru_cache
from pathlib import Path


UNKNOWN_METADATA = {
    "version": "unknown",
    "build_time": "unknown",
    "branch": "unknown",
    "commit": "unknown",
    "commit_message": "unknown",
}


def _build_info_path() -> Path:
    override = os.getenv("DEERFLOW_BACKEND_BUILD_INFO_PATH")
    if override:
        return Path(override)

    return Path(__file__).resolve().parents[1] / "build_info.json"


@lru_cache(maxsize=1)
def get_backend_build_info() -> dict[str, str]:
    path = _build_info_path()
    if not path.exists():
        return dict(UNKNOWN_METADATA)

    try:
        data = json.loads(path.read_text())
    except Exception:
        return dict(UNKNOWN_METADATA)

    return {
        "version": str(data.get("version") or "unknown"),
        "build_time": str(data.get("build_time") or "unknown"),
        "branch": str(data.get("branch") or "unknown"),
        "commit": str(data.get("commit") or "unknown"),
        "commit_message": str(data.get("commit_message") or "unknown"),
    }
