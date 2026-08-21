"""Fast checks for the database URL normalization used by Supabase."""

from app.config.settings import Settings


def test_supabase_libpq_url_becomes_an_asyncpg_url() -> None:
    settings = Settings(
        database_url="postgresql://postgres:password@db.example.supabase.co:5432/postgres?sslmode=require"
    )

    assert settings.async_database_url == (
        "postgresql+asyncpg://postgres:password@db.example.supabase.co:5432/postgres?ssl=require"
    )


def test_database_configuration_fails_closed_when_missing() -> None:
    settings = Settings(database_url=None)

    assert settings.async_database_url is None
