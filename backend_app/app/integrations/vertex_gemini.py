"""Small, provider-specific Vertex Gemini client factory.

The application uses the supported Google Gen AI SDK directly.  It deliberately
does not introduce a generic agent framework for one structured extraction
call, which keeps configuration, latency, and provider failure modes explicit.
"""

from __future__ import annotations

from google.genai import Client
from google.genai.types import HttpOptions

from app.config.settings import Settings
from app.retrieval.vertex import load_vertex_authentication


def create_vertex_gemini_client(settings: Settings) -> Client:
    """Create a v1 Vertex AI Gemini client using server-only credentials."""

    auth = load_vertex_authentication(settings)
    return Client(
        vertexai=True,
        project=auth.project_id,
        location=settings.google_cloud_location,
        credentials=auth.credentials,
        http_options=HttpOptions(api_version="v1"),
    )
