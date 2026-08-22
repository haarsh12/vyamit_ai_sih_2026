"""Tests for the configured LiveKit voice-agent provider stack."""

from app.agent.providers import create_llm, create_stt, create_tts
from app.config.settings import get_settings


def test_stt_provider_is_google():
    """The new architecture uses Google Cloud STT, not the legacy Deepgram path."""
    settings = get_settings()
    stt = create_stt(settings)

    assert stt is not None
    assert "google" in str(type(stt)).lower()
    assert settings.google_stt_model == "latest_long"


def test_tts_provider_is_cartesia():
    """Verify TTS is configured to use Cartesia."""
    settings = get_settings()
    tts = create_tts(settings)
    assert tts is not None
    assert "cartesia" in str(type(tts)).lower()


def test_llm_has_fallback_adapter():
    """Verify LLM uses FallbackAdapter with Gemini primary and Mistral fallback."""
    settings = get_settings()
    llm = create_llm(settings)
    assert llm is not None
    assert "FallbackAdapter" in str(type(llm))


def test_required_environment_variables_are_set():
    """Verify all required environment variables for voice agent are configured."""
    settings = get_settings()
    
    # Cartesia
    assert settings.cartesia_api_key is not None, "CARTESIA_API_KEY must be set"
    assert settings.cartesia_voice_id != "", "CARTESIA_VOICE_ID must be set"
    
    # Mistral
    assert settings.mistral_api_key is not None, "MISTRAL_API_KEY must be set"
    assert settings.mistral_model != "", "MISTRAL_MODEL must be set"
    
    # Google credentials serve both STT and the Vertex Gemini primary LLM.
    assert settings.google_application_credentials is not None, "GOOGLE_APPLICATION_CREDENTIALS must be set"
    assert settings.google_credentials_path.is_file()
    assert settings.google_cloud_project != ""
    assert settings.google_stt_model == "latest_long"
    assert settings.vertex_gemini_model != "", "VERTEX_GEMINI_MODEL must be set"
    
    # LiveKit
    assert settings.livekit_url != "", "LIVEKIT_URL must be set"
    assert settings.livekit_api_key is not None, "LIVEKIT_API_KEY must be set"

def test_agent_configuration_passes_runtime_validation():
    get_settings().require_agent_providers()
