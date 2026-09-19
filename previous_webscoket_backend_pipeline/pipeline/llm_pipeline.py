"""LLM pipeline using LangChain for robust model handling."""

import json
import logging
import os
import time
from typing import Any, Dict, Tuple

from .config import config

logger = logging.getLogger(__name__)

ERROR_RESPONSE: Dict[str, Any] = {
    "type": "ERROR",
    "items": [],
    "msg": "AI service temporarily unavailable. Please try again.",
    "should_stop": False,
}


class LLMPipeline:
    """Invoke LLMs using LangChain with automatic fallback."""

    def __init__(self) -> None:
        self.gemini_api_key = os.getenv("GEMINI_API_KEY", "").strip()
        self.mistral_api_key = os.getenv("MISTRAL_API_KEY", "").strip()
        self._gemini_llm = None
        self._mistral_llm = None

    def _init_gemini(self):
        """Initialize Gemini LLM using LangChain."""
        if self._gemini_llm is not None:
            return True
        if not self.gemini_api_key:
            return False

        try:
            from langchain_google_genai import ChatGoogleGenerativeAI
            
            # Use gemini-flash-latest (stable alias that works for all users)
            self._gemini_llm = ChatGoogleGenerativeAI(
                model="gemini-flash-latest",
                google_api_key=self.gemini_api_key,
                temperature=config.llm.fallback_temperature,
                max_tokens=config.llm.fallback_max_tokens,
            )
            logger.info("Gemini LLM initialized via LangChain (gemini-flash-latest)")
            return True
        except Exception as exc:
            logger.error(f"Gemini initialization failed: {exc}")
            return False

    def _init_mistral(self):
        """Initialize Mistral LLM using LangChain."""
        if self._mistral_llm is not None:
            return True
        if not self.mistral_api_key:
            return False

        try:
            from langchain_mistralai import ChatMistralAI
            
            # Try the configured model, fallback to free tier model if needed
            self._mistral_llm = ChatMistralAI(
                model=config.llm.primary_model,
                mistral_api_key=self.mistral_api_key,
                temperature=config.llm.primary_temperature,
                max_tokens=config.llm.primary_max_tokens,
            )
            logger.info(f"Mistral LLM initialized via LangChain (model: {config.llm.primary_model})")
            return True
        except Exception as exc:
            logger.warning(f"Mistral initialization failed: {exc}")
            # Try free tier model as fallback
            try:
                self._mistral_llm = ChatMistralAI(
                    model="mistral-small-latest",  # Free tier model
                    mistral_api_key=self.mistral_api_key,
                    temperature=config.llm.primary_temperature,
                    max_tokens=config.llm.primary_max_tokens,
                )
                logger.info("Mistral LLM initialized with free tier model (mistral-small-latest)")
                return True
            except Exception as fallback_exc:
                logger.warning(f"Mistral free tier fallback also failed: {fallback_exc}")
                return False

    @staticmethod
    def _parse_json_response(content: str) -> Dict[str, Any]:
        """Parse model JSON, accepting a surrounding markdown code fence."""
        if not isinstance(content, str) or not content.strip():
            raise ValueError("Model returned an empty response.")

        cleaned = content.strip()
        if cleaned.startswith("```"):
            lines = cleaned.splitlines()
            if lines[-1].strip() == "```":
                cleaned = "\n".join(lines[1:-1]).strip()
            elif lines[0].startswith("```json"):
                cleaned = "\n".join(lines[1:]).strip()
                if cleaned.endswith("```"):
                    cleaned = cleaned[:-3].strip()

        parsed = json.loads(cleaned)
        if not isinstance(parsed, dict):
            raise ValueError("Model response must be a JSON object.")
        return parsed

    def invoke_mistral(self, prompt: str) -> Tuple[Dict[str, Any], float]:
        """Invoke Mistral via LangChain."""
        if not self._init_mistral():
            raise RuntimeError("Mistral is not configured.")

        start = time.perf_counter()
        try:
            response = self._mistral_llm.invoke(prompt)
            parsed = self._parse_json_response(response.content)
            duration = time.perf_counter() - start
            logger.info(f"Mistral response in {duration * 1000:.2f}ms")
            return parsed, duration
        except Exception as exc:
            logger.warning(f"Mistral invocation failed: {exc}")
            raise

    def invoke_gemini(self, prompt: str) -> Tuple[Dict[str, Any], float]:
        """Invoke Gemini via LangChain."""
        if not self._init_gemini():
            raise RuntimeError("Gemini is not configured.")

        start = time.perf_counter()
        try:
            response = self._gemini_llm.invoke(prompt)
            
            # Handle response content - might be string or list
            content = response.content
            if isinstance(content, list):
                # Join list items into a single string
                content = " ".join(str(item) for item in content)
            elif not isinstance(content, str):
                content = str(content)
            
            # Log the full response for debugging
            print(f"\n{'='*60}\nGemini Response:\n{content}\n{'='*60}\n")
            
            if not content or not content.strip():
                raise ValueError("Model returned an empty response. This may be due to content filtering or prompt issues.")
            
            parsed = self._parse_json_response(content)
            duration = time.perf_counter() - start
            logger.info(f"Gemini response in {duration * 1000:.2f}ms")
            return parsed, duration
        except Exception as exc:
            logger.error(f"Gemini invocation failed: {exc}")
            raise

    def invoke(self, prompt: str) -> Tuple[Dict[str, Any], float, str]:
        """Invoke the primary model with fallback; never expose raw provider errors."""
        if not isinstance(prompt, str) or not prompt.strip():
            return {
                **ERROR_RESPONSE,
                "msg": "Please provide a question or billing request.",
            }, 0.0, "error"

        # Try Mistral first (if configured)
        if self.mistral_api_key:
            try:
                response, duration = self.invoke_mistral(prompt)
                return response, duration, config.llm.primary_model
            except Exception as e:
                logger.warning(f"Mistral failed, trying Gemini: {e}")
        else:
            logger.info("Mistral not configured, using Gemini")

        # Try Gemini fallback
        if self.gemini_api_key:
            try:
                response, duration = self.invoke_gemini(prompt)
                return response, duration, "gemini-flash-latest"
            except Exception as exc:
                logger.error(f"All LLM providers failed: {exc}")
        else:
            logger.error("No LLM API keys configured")

        return ERROR_RESPONSE.copy(), 0.0, "error"

    @staticmethod
    def validate_response(response: Dict[str, Any]) -> bool:
        """Validate the API contract returned by either provider."""
        required_fields = {"type", "items", "msg", "should_stop"}
        if not isinstance(response, dict) or not required_fields.issubset(response):
            logger.warning("Invalid response structure - missing fields")
            return False
        if response["type"] not in {"BILL", "QUERY", "ERROR"}:
            logger.warning(f"Invalid response type: {response['type']}")
            return False
        if not isinstance(response["items"], list):
            logger.warning("Items field is not a list")
            return False
        if not isinstance(response["msg"], str) or not isinstance(response["should_stop"], bool):
            logger.warning("Response contains fields with invalid types")
            return False
        return True


llm_pipeline = LLMPipeline()
