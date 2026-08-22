"""Typed, server-only settings for the Vyamit API and LiveKit worker."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuration loaded from the environment, never from Flutter."""

    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: str = "development"
    app_name: str = "Vyamit Backend"
    api_host: str = "127.0.0.1"
    api_port: int = 8000
    cors_origins: str = "http://localhost:3000,http://localhost:8080"

    jwt_secret_key: SecretStr | None = None
    jwt_access_token_minutes: int = Field(default=60 * 24 * 7, ge=5, le=60 * 24 * 30)

    database_url: SecretStr | None = None
    supabase_url: str | None = None
    supabase_service_role_key: SecretStr | None = None

    livekit_url: str = ""
    livekit_api_key: SecretStr | None = None
    livekit_api_secret: SecretStr | None = None
    livekit_agent_name: str = "vyamit-voice"
    livekit_token_minutes: int = Field(default=15, ge=5, le=60)

    google_application_credentials: str | None = None
    google_cloud_project: str = ""
    google_cloud_location: str = "global"
    # `latest_long` is supported by the installed Google STT integration and
    # supports streaming recognition. Newer Chirp model identifiers vary by
    # Google Speech API generation and must not be used without an upgrade.
    google_stt_model: str = "latest_long"
    google_stt_languages: str = "hi-IN,mr-IN,en-IN"
    google_keyterms: str = "Vyamit,व्यामित,नमस्ते,धन्यवाद,मराठी"
    vertex_gemini_model: str = ""
    vertex_embedding_model: str = "text-embedding-004"
    vertex_embedding_dimension: int = Field(default=768, ge=1, le=4096)

    cartesia_api_key: SecretStr | None = None
    cartesia_tts_model: str = "sonic-3"
    cartesia_voice_id: str = ""
    mistral_api_key: SecretStr | None = None
    mistral_model: str = ""

    fast2sms_api_key: SecretStr | None = None
    fast2sms_base_url: str = "https://www.fast2sms.com/dev/bulkV2"
    otp_demo_mode: bool = False
    log_otp_codes: bool = False
    enable_enhanced_noise_cancellation: bool = False

    @field_validator("app_env")
    @classmethod
    def normalise_environment(cls, value: str) -> str:
        return value.strip().lower()

    @property
    def allowed_origins(self) -> list[str]:
        return [value.strip().rstrip("/") for value in self.cors_origins.split(",") if value.strip()]

    @property
    def stt_languages(self) -> list[str]:
        return [value.strip() for value in self.google_stt_languages.split(",") if value.strip()]

    @property
    def keyterms(self) -> list[str]:
        return [value.strip() for value in self.google_keyterms.split(",") if value.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env in {"production", "prod"}

    @property
    def async_database_url(self) -> str | None:
        if self.database_url is None:
            return None
        value = self.database_url.get_secret_value().strip()
        if not value:
            return None
        if value.startswith("postgres://"):
            value = "postgresql://" + value.removeprefix("postgres://")
        if value.startswith("postgresql://"):
            # Supabase documents its connection string with psycopg/libpq's
            # `sslmode` query option. asyncpg uses the equivalent `ssl` name.
            return (
                "postgresql+asyncpg://" + value.removeprefix("postgresql://")
            ).replace("sslmode=", "ssl=")
        return value

    def require_database(self) -> str:
        value = self.async_database_url
        if not value:
            raise RuntimeError("DATABASE_URL must be configured for this operation.")
        return value

    def require_jwt_secret(self) -> str:
        if self.jwt_secret_key is None or not self.jwt_secret_key.get_secret_value().strip():
            raise RuntimeError("JWT_SECRET_KEY must be configured.")
        return self.jwt_secret_key.get_secret_value()

    def require_livekit(self) -> None:
        missing = [
            name
            for name, value in (
                ("LIVEKIT_URL", self.livekit_url),
                ("LIVEKIT_API_KEY", self.livekit_api_key),
                ("LIVEKIT_API_SECRET", self.livekit_api_secret),
            )
            if not _has_value(value)
        ]
        if missing:
            raise RuntimeError(f"Missing LiveKit configuration: {', '.join(missing)}")

    def require_sms_delivery(self) -> None:
        if self.otp_demo_mode:
            return
        if not _has_value(self.fast2sms_api_key):
            raise RuntimeError("FAST2SMS_API_KEY must be configured unless OTP_DEMO_MODE is enabled.")

    def require_api_runtime_security(self) -> None:
        """Fail fast on production-only insecure configuration."""

        if not self.is_production:
            return
        self.require_jwt_secret()
        if self.otp_demo_mode or self.log_otp_codes:
            raise RuntimeError("OTP demo mode and OTP code logging are forbidden in production.")
        if not self.allowed_origins or any(not origin.startswith("https://") for origin in self.allowed_origins):
            raise RuntimeError("CORS_ORIGINS must contain explicit HTTPS origins in production.")

    def require_agent_providers(self) -> None:
        self.require_livekit()
        required = [
            ("GOOGLE_APPLICATION_CREDENTIALS", self.google_application_credentials),
            ("VERTEX_GEMINI_MODEL", self.vertex_gemini_model),
            ("CARTESIA_API_KEY", self.cartesia_api_key),
            ("CARTESIA_VOICE_ID", self.cartesia_voice_id),
            ("MISTRAL_API_KEY", self.mistral_api_key),
            ("MISTRAL_MODEL", self.mistral_model),
        ]
        missing = [name for name, value in required if not _has_value(value)]
        if missing:
            raise RuntimeError(f"Missing agent provider configuration: {', '.join(missing)}")
        credential_path = self.google_credentials_path
        if not credential_path.is_file():
            raise RuntimeError("GOOGLE_APPLICATION_CREDENTIALS must point to a mounted credential file.")

    @property
    def google_credentials_path(self) -> Path:
        """Resolve a local credential filename relative to the backend root."""

        configured = Path(self.google_application_credentials or "")
        if configured.is_absolute():
            return configured
        return Path(__file__).resolve().parents[2] / configured


def _has_value(value: str | SecretStr | None) -> bool:
    if value is None:
        return False
    if isinstance(value, SecretStr):
        return bool(value.get_secret_value().strip())
    return bool(value.strip())


@lru_cache
def get_settings() -> Settings:
    """Return one settings instance per process."""

    return Settings()
