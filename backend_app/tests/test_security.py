from app.config.settings import Settings
from app.core.security import create_access_token, decode_access_token


def test_jwt_requires_and_round_trips_a_configured_secret() -> None:
    settings = Settings(jwt_secret_key="this-is-a-test-secret-with-sufficient-length")
    token = create_access_token(subject=42, settings=settings)
    assert decode_access_token(token, settings=settings) == 42


def test_jwt_fails_closed_without_a_secret() -> None:
    assert decode_access_token("not-a-token", settings=Settings()) is None
