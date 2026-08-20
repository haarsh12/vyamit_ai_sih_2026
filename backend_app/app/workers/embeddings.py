"""Transactional-outbox worker for inventory embeddings; run as a separate process."""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.db.models import EmbeddingJob, Item
from app.db.session import get_session_factory
from app.retrieval.embeddings import EmbeddingServiceError, VertexEmbeddingService
from app.repositories.inventory import item_embedding_source_hash


logger = logging.getLogger(__name__)


class EmbeddingOutboxWorker:
    def __init__(self, service: VertexEmbeddingService | None = None) -> None:
        self.service = service or VertexEmbeddingService()

    async def run_once(self, *, limit: int = 25) -> int:
        factory = get_session_factory()
        if factory is None:
            raise RuntimeError("DATABASE_URL is required for the embedding worker.")
        processed = 0
        async with factory() as session:
            now = datetime.now(UTC)
            jobs = (await session.scalars(select(EmbeddingJob).where(
                EmbeddingJob.status == "pending", EmbeddingJob.available_at <= now
            ).order_by(EmbeddingJob.created_at).with_for_update(skip_locked=True).limit(limit))).all()
            for job in jobs:
                processed += 1
                job.status, job.attempts = "processing", job.attempts + 1
                item = await session.get(Item, job.entity_id) if job.entity_type == "item" else None
                if item is None or job.operation == "delete":
                    job.status = "completed"
                    continue
                source_hash = item_embedding_source_hash(item)
                if item.embedding_source_hash == source_hash and item.embedding is not None:
                    job.status = "completed"
                    continue
                try:
                    vector = await self.service.embed_documents([" ".join([*item.names, item.category, item.unit])])
                    item.embedding = vector[0]
                    item.embedding_source_hash = source_hash
                    item.embedding_model = self.service.settings.vertex_embedding_model
                    item.embedding_updated_at = datetime.now(UTC)
                    job.status, job.last_error_code = "completed", None
                except EmbeddingServiceError as error:
                    job.last_error_code = type(error).__name__
                    if job.attempts >= 5:
                        job.status = "failed"
                    else:
                        job.status = "pending"
                        job.available_at = now + timedelta(seconds=min(300, 2 ** job.attempts))
            await session.commit()
        return processed


async def main() -> None:
    worker = EmbeddingOutboxWorker()
    while True:
        try:
            processed = await worker.run_once()
            await asyncio.sleep(0.25 if processed else 2)
        except Exception:
            logger.exception("embedding_worker_cycle_failed")
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(main())
