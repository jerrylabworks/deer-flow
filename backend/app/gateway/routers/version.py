import os

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.build_info import get_backend_build_info


router = APIRouter(prefix="/api", tags=["version"])


def _value(name: str) -> str:
    value = os.getenv(name)
    return value if value else "unknown"


class BuildMetadata(BaseModel):
    version: str = Field(description="Application version")
    build_time: str = Field(description="Build timestamp")
    branch: str = Field(description="Source control branch name")
    commit: str = Field(description="Source control commit hash")
    commit_message: str = Field(description="Source control commit message")


class VersionResponse(BaseModel):
    frontend: BuildMetadata
    backend: BuildMetadata


@router.get("/version", response_model=VersionResponse, summary="Get build version information")
async def get_version() -> VersionResponse:
    return VersionResponse(
        frontend=BuildMetadata(
            version=_value("FRONTEND_VERSION"),
            build_time=_value("FRONTEND_BUILD_TIME"),
            branch=_value("FRONTEND_BUILD_BRANCH"),
            commit=_value("FRONTEND_BUILD_COMMIT"),
            commit_message=_value("FRONTEND_BUILD_COMMIT_MESSAGE"),
        ),
        backend=BuildMetadata(
            **get_backend_build_info(),
        ),
    )
