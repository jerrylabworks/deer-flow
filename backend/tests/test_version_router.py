from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import build_info
from app.gateway.routers.version import router


def test_version_endpoint_returns_frontend_and_backend_metadata_defaults(monkeypatch, tmp_path: Path):
    build_info.get_backend_build_info.cache_clear()
    monkeypatch.setenv(
        "DEERFLOW_BACKEND_BUILD_INFO_PATH",
        str(tmp_path / "missing-build-info.json"),
    )
    app = FastAPI()
    app.include_router(router)

    with TestClient(app) as client:
        response = client.get("/api/version")

    assert response.status_code == 200
    payload = response.json()

    assert payload["frontend"]["version"] == "unknown"
    assert payload["frontend"]["build_time"] == "unknown"
    assert payload["frontend"]["branch"] == "unknown"
    assert payload["frontend"]["commit"] == "unknown"
    assert payload["frontend"]["commit_message"] == "unknown"

    assert payload["backend"]["version"] == "unknown"
    assert payload["backend"]["build_time"] == "unknown"
    assert payload["backend"]["branch"] == "unknown"
    assert payload["backend"]["commit"] == "unknown"
    assert payload["backend"]["commit_message"] == "unknown"

    build_info.get_backend_build_info.cache_clear()


def test_version_endpoint_reads_backend_metadata_from_override_file(monkeypatch, tmp_path: Path):
    build_info.get_backend_build_info.cache_clear()
    build_info_path = tmp_path / "build_info.json"
    build_info_path.write_text(
        """{
  \"version\": \"9.9.9\",
  \"build_time\": \"2026-04-09T00:00:00Z\",
  \"branch\": \"release/test\",
  \"commit\": \"deadbeef\",
  \"commit_message\": \"test release metadata\"
}
"""
    )
    monkeypatch.setenv("DEERFLOW_BACKEND_BUILD_INFO_PATH", str(build_info_path))

    app = FastAPI()
    app.include_router(router)

    with TestClient(app) as client:
        response = client.get("/api/version")

    assert response.status_code == 200
    payload = response.json()
    assert payload["backend"] == {
        "version": "9.9.9",
        "build_time": "2026-04-09T00:00:00Z",
        "branch": "release/test",
        "commit": "deadbeef",
        "commit_message": "test release metadata",
    }

    build_info.get_backend_build_info.cache_clear()
