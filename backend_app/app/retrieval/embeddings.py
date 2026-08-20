"""Vertex embedding service with fixed vector-shape guarantees."""

from __future__ import annotations

import asyncio
from collections.abc import Sequence
from functools import cached_property

from app.config.settings import Settings, get_settings
from app.retrieval.vertex import load_vertex_authentication


class EmbeddingServiceError(RuntimeError):
    """Provider-safe failure raised without leaking credentials or request content."""


class VertexEmbeddingService:
    """Creates embeddings only for indexing or a selected semantic-retrieval tool."""

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        # The initial migration uses vector(768). Refuse incompatible values before a corrupt write.
        if self.settings.vertex_embedding_dimension != 768:
            raise EmbeddingServiceError("VERTEX_EMBEDDING_DIMENSION must be 768 for the current schema.")

    @cached_property
    def _model(self):
        try:
            import vertexai
            from vertexai.language_models import TextEmbeddingModel

            auth = load_vertex_authentication(self.settings)
            vertexai.init(
                project=auth.project_id,
                location=self.settings.google_cloud_location,
                credentials=auth.credentials,
            )
            return TextEmbeddingModel.from_pretrained(self.settings.vertex_embedding_model)
        except Exception as error:
            raise EmbeddingServiceError("Vertex embedding service could not be initialised.") from error

    def _embed_blocking(self, texts: Sequence[str], task_type: str) -> list[list[float]]:
        if not texts or any(not text.strip() for text in texts):
            raise EmbeddingServiceError("Embedding input must contain non-empty text.")
        try:
            from vertexai.language_models import TextEmbeddingInput

            inputs = [TextEmbeddingInput(text, task_type=task_type) for text in texts]
            result = self._model.get_embeddings(
                inputs, output_dimensionality=self.settings.vertex_embedding_dimension
            )
            values = [list(row.values) for row in result]
        except EmbeddingServiceError:
            raise
        except Exception as error:
            raise EmbeddingServiceError("Vertex embedding request failed.") from error
        if len(values) != len(texts) or any(len(value) != self.settings.vertex_embedding_dimension for value in values):
            raise EmbeddingServiceError("Vertex embedding response did not match the configured dimension.")
        return values

    async def embed_documents(self, texts: Sequence[str]) -> list[list[float]]:
        return await asyncio.to_thread(self._embed_blocking, texts, "RETRIEVAL_DOCUMENT")

    async def embed_query(self, text: str) -> list[float]:
        return (await asyncio.to_thread(self._embed_blocking, [text], "RETRIEVAL_QUERY"))[0]
