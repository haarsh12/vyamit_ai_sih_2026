"""LiveKit provider factories using the tested reference integrations and real fallback."""

from __future__ import annotations

from google.genai.types import HttpOptions
from livekit.agents import llm
from livekit.plugins import cartesia, google, mistralai

from app.config.settings import Settings
from app.retrieval.vertex import load_vertex_authentication


def create_stt(settings: Settings) -> google.STT:
    keywords = [(term, 5.0) for term in settings.keyterms] or None
    return google.STT(
        languages=settings.stt_languages,
        model=settings.google_stt_model,
        project=settings.google_cloud_project,
        location=settings.google_cloud_location,
        credentials_file=str(settings.google_credentials_path),
        spoken_punctuation=True,
        keywords=keywords,
    )


def create_primary_llm(settings: Settings) -> google.LLM:
    authentication = load_vertex_authentication(settings)
    return google.LLM(
        model=settings.vertex_gemini_model,
        vertexai=True,
        project=authentication.project_id,
        location=settings.google_cloud_location,
        credentials=authentication.credentials,
        temperature=0.25,
        http_options=HttpOptions(api_version="v1"),
    )


def create_llm(settings: Settings) -> llm.FallbackAdapter:
    """Try Gemini first; a transient provider failure switches to Mistral, never parallel calls."""

    primary = create_primary_llm(settings)
    fallback = mistralai.LLM(
        model=settings.mistral_model,
        api_key=settings.mistral_api_key.get_secret_value(),
        temperature=0.25,
    )
    return llm.FallbackAdapter(
        llm=[primary, fallback], attempt_timeout=12.0, max_retry_per_llm=0, retry_interval=0.5,
    )


def create_tts(settings: Settings) -> cartesia.TTS:
    return cartesia.TTS(
        model=settings.cartesia_tts_model,
        voice=settings.cartesia_voice_id,
        api_key=settings.cartesia_api_key.get_secret_value(),
        language="en",
        speed=1.0,
    )
