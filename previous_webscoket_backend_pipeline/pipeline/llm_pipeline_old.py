"""LLM pipeline with Mistral primary and Gemini fallback providers."""

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
    """Invoke Mistral, then Gemini, and always return the shared response shape."""

    def __init__(self) -> None:
        self.mistral_api_key = os.getenv("MISTRAL_API_KEY", "").strip()
        self.gemini_api_key = os.getenv("GEMINI_API_KEY", "").strip()
        self._mistral_client = None
        self._gemini_client = None
        self._gemini_types = None

    def _init_mistral(self) -> bool:
        """Create a Mistral client across supported SDK versions."""
        if self._mistral_client is not None:
            return True
        if not self.mistral_api_key:
            return False

        try:
            # Try current Mistral SDK (1.0+)
            from mistralai import Mistral
            self._mistral_client = Mistral(api_key=self.mistral_api_key)
            logger.info("Mistral client initialized (v1.0+)")
            return True
        except (ImportError, AttributeError):
            pass

        try:
            # Try legacy SDK (0.x)
            from mistralai.client import MistralClient
            self._mistral_client = MistralClient(api_key=self.mistral_api_key)
            logger.info("Mistral client initialized (legacy)")
            return True
        except (ImportError, AttributeError):
            pass

        logger.warning("Mistral SDK not found or incompatible")
        return False

    def _init_gemini(self) -> bool:
        """Create a client for the supported Google Gen AI SDK."""
        if self._gemini_client is not None:
            return True
        if not self.gemini_api_key:
            return False

        try:
            from google import genai
            from google.genai import types

            self._gemini_client = genai.Client(api_key=self.gemini_api_key)
            self._gemini_types = types
        except Exception as exc:
            logger.error("Gemini initialization failed: %s", exc)
            return False

        logger.info("Gemini client initialized")
        return True

    @staticmethod
    def _parse_json_response(content: str) -> Dict[str, Any]:
        """Parse model JSON, accepting a surrounding markdown code fence."""
        if not isinstance(content, str) or not content.strip():
            raise ValueError("Model returned an empty response.")

        cleaned = content.strip()
        if cleaned.startswith("```"):
            lines = cleaned.splitlines()
            if lines[-1].strip() != "```":
                raise ValueError("Model returned an unterminated markdown code block.")
            cleaned = "\n".join(lines[1:-1]).strip()

        parsed = json.loads(cleaned)
        if not isinstance(parsed, dict):
            raise ValueError("Model response must be a JSON object.")
        return parsed

    def invoke_mistral(self, prompt: str) -> Tuple[Dict[str, Any], float]:
        """Invoke Mistral and return its parsed JSON response."""
        if not self._init_mistral():
            raise RuntimeError("Mistral client is not configured.")

        start = time.perf_counter()
        chat = self._mistral_client.chat
        kwargs = {
            "model": config.llm.primary_model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": config.llm.primary_temperature,
            "max_tokens": config.llm.primary_max_tokens,
        }
        try:
            response = chat.complete(**kwargs) if hasattr(chat, "complete") else chat(**kwargs)
            parsed = self._parse_json_response(response.choices[0].message.content)
        except Exception as exc:
            logger.warning("Mistral invocation failed: %s", exc)
            raise

        duration = time.perf_counter() - start
        logger.info("Mistral response in %.2fms", duration * 1000)
        return parsed, duration

    def invoke_gemini(self, prompt: str) -> Tuple[Dict[str, Any], float]:
        """Invoke configured Gemini fallback models until one returns valid JSON."""
        if not self._init_gemini():
            raise RuntimeError("Gemini client is not configured.")

        start = time.perf_counter()
        errors = []
        for model_name in config.llm.fallback_models:
            try:
                response = self._gemini_client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=self._gemini_types.GenerateContentConfig(
                        temperature=config.llm.fallback_temperature,
                        max_output_tokens=config.llm.fallback_max_tokens,
                        response_mime_type="application/json",
                    ),
                )
                parsed = self._parse_json_response(response.text)
                duration = time.perf_counter() - start
                logger.info("Gemini (%s) response in %.2fms", model_name, duration * 1000)
                return parsed, duration
            except Exception as exc:
                errors.append(f"{model_name}: {exc}")
                logger.warning("Gemini model %s failed: %s", model_name, exc)

        raise RuntimeError("All Gemini fallback models failed: " + "; ".join(errors))

    def invoke(self, prompt: str) -> Tuple[Dict[str, Any], float, str]:
        """Invoke the primary model with fallback; never expose raw provider errors."""
        if not isinstance(prompt, str) or not prompt.strip():
            return {
                **ERROR_RESPONSE,
                "msg": "Please provide a question or billing request.",
            }, 0.0, "error"

        if self.mistral_api_key:
            try:
                response, duration = self.invoke_mistral(prompt)
                return response, duration, config.llm.primary_model
            except Exception:
                logger.info("Falling back from Mistral to Gemini")

        if self.gemini_api_key:
            try:
                response, duration = self.invoke_gemini(prompt)
                return response, duration, "gemini-fallback"
            except Exception as exc:
                logger.error("All configured LLM providers failed: %s", exc)

        return ERROR_RESPONSE.copy(), 0.0, "error"

    @staticmethod
    def validate_response(response: Dict[str, Any]) -> bool:
        """Validate the API contract returned by either provider."""
        required_fields = {"type", "items", "msg", "should_stop"}
        if not isinstance(response, dict) or not required_fields.issubset(response):
            logger.warning("Invalid response structure - missing fields")
            return False
        if response["type"] not in {"BILL", "QUERY", "ERROR"}:
            logger.warning("Invalid response type: %s", response["type"])
            return False
        if not isinstance(response["items"], list):
            logger.warning("Items field is not a list")
            return False
        if not isinstance(response["msg"], str) or not isinstance(response["should_stop"], bool):
            logger.warning("Response contains fields with invalid types")
            return False
        return True


llm_pipeline = LLMPipeline()
