"""LiveKit provider factories optimized for low latency realtime voice."""

from __future__ import annotations

from google.genai.types import HttpOptions
from livekit.plugins import google

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
    """Create Gemini LLM optimized for ultra-low latency voice responses."""
    
    authentication = load_vertex_authentication(settings)
    return google.LLM(
        model=settings.vertex_gemini_model,
        vertexai=True,
        project=authentication.project_id,
        location=settings.google_cloud_location,
        credentials=authentication.credentials,
        temperature=0.3,  # Slightly higher for better function call generation
        http_options=HttpOptions(api_version="v1"),
        # Streaming configuration for faster perceived response time
        max_output_tokens=512,  # Increased for complex function calls
        top_p=0.95,
        top_k=40,
    )


def create_tts(settings: Settings) -> google.TTS:
    """Create Google Cloud TTS with the server's service-account credentials."""

    return google.TTS(
        language=settings.google_tts_language,
        model_name=settings.google_tts_model,
        location=settings.google_cloud_location,
        credentials_file=str(settings.google_credentials_path),
        speaking_rate=settings.google_tts_speaking_rate,
    )
