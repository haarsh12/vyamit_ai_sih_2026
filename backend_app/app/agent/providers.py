"""LiveKit provider factories optimized for low latency realtime voice."""

from __future__ import annotations

from google.genai.types import HttpOptions
from livekit.plugins import cartesia, google

from app.config.settings import Settings
from app.retrieval.vertex import load_vertex_authentication


def create_stt(settings: Settings) -> google.STT:
    """Create streaming Google Cloud STT with multilingual support and code-switching."""
    
    keywords = [(term, 5.0) for term in settings.keyterms] if settings.keyterms else None
    
    return google.STT(
        languages=settings.stt_languages,
        model=settings.google_stt_model,
        project=settings.google_cloud_project,
        location=settings.google_cloud_location,
        credentials_file=str(settings.google_credentials_path),
        spoken_punctuation=True,
        keywords=keywords,
    )


def create_llm(settings: Settings) -> google.LLM:
    """Create Gemini LLM directly without fallback adapter for faster responses."""
    
    authentication = load_vertex_authentication(settings)
    return google.LLM(
        model=settings.vertex_gemini_model,
        vertexai=True,
        project=authentication.project_id,
        location=settings.google_cloud_location,
        credentials=authentication.credentials,
        temperature=0.3,  # Slightly higher for more natural responses
        http_options=HttpOptions(api_version="v1"),
    )


def create_tts(settings: Settings) -> cartesia.TTS:
    """Create Cartesia TTS with dynamic language support."""
    
    return cartesia.TTS(
        model=settings.cartesia_tts_model,
        voice=settings.cartesia_voice_id,
        api_key=settings.cartesia_api_key.get_secret_value(),
        language="en",  # Will be updated dynamically based on detected speech language
        speed=1.1,  # Slightly faster for more responsive feel
    )
