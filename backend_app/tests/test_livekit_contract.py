import inspect

from livekit.agents import AgentSession, JobContext

from app.agent.providers import create_llm


def test_livekit_shutdown_and_start_contract_matches_runner_usage() -> None:
    assert "reason" in inspect.signature(JobContext.shutdown).parameters
    assert inspect.iscoroutinefunction(AgentSession.start)


def test_provider_factory_returns_the_documented_fallback_adapter_type() -> None:
    # The settings-free check intentionally validates the declared factory
    # contract without calling external Gemini, Mistral, or Cartesia services.
    assert create_llm.__annotations__["return"] == "llm.FallbackAdapter"
