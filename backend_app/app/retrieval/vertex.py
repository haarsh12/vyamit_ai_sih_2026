"""Google service-account authentication shared by Gemini and Vertex embeddings."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from google.auth.credentials import Credentials
from google.oauth2 import service_account

from app.config.settings import Settings


_CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"


@dataclass(frozen=True, slots=True)
class VertexAuthentication:
    credentials: Credentials
    project_id: str


def load_vertex_authentication(settings: Settings) -> VertexAuthentication:
    """Load a file-mounted service account and infer its project where permitted."""

    credential_path = settings.google_credentials_path
    if not credential_path.is_file():
        raise RuntimeError("GOOGLE_APPLICATION_CREDENTIALS must reference a readable mounted credential file.")
    credentials = service_account.Credentials.from_service_account_file(
        str(credential_path), scopes=[_CLOUD_PLATFORM_SCOPE]
    )
    project_id = settings.google_cloud_project or credentials.project_id
    if not project_id:
        raise RuntimeError("GOOGLE_CLOUD_PROJECT is required when the credential contains no project_id.")
    return VertexAuthentication(credentials=credentials, project_id=project_id)
