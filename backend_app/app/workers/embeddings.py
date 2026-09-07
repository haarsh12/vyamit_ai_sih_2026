"""Transactional-outbox worker for inventory and customer embeddings; run as a separate process."""

from __future__ import annotations

import asyncio
import hashlib
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.db.models import EmbeddingJob, Item, VerifiedCustomer
from app.db.session import get_session_factory
from app.retrieval.embeddings import EmbeddingServiceError, VertexEmbeddingService
from app.repositories.inventory import item_embedding_source_hash


logger = logging.getLogger(__name__)


def verified_customer_embedding_source_hash(customer: VerifiedCustomer) -> str:
    """Generate a stable hash from customer name to detect when re-embedding is needed."""
    source = customer.name.strip().lower()
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


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
                
                # Handle item embeddings
                if job.entity_type == "item":
                    item = await session.get(Item, job.entity_id)
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
                
                # Handle verified customer embeddings
                elif job.entity_type == "verified_customer":
                    customer = await session.get(VerifiedCustomer, job.entity_id)
                    if customer is None or job.operation == "delete":
                        job.status = "completed"
                        continue
                    
                    source_hash = verified_customer_embedding_source_hash(customer)
                    if customer.embedding_source_hash == source_hash and customer.name_embedding is not None:
                        job.status = "completed"
                        continue
                    
                    try:
                        # Embed customer name for semantic search
                        vector = await self.service.embed_documents([customer.name.strip()])
                        customer.name_embedding = vector[0]
                        customer.embedding_source_hash = source_hash
                        customer.embedding_model = self.service.settings.vertex_embedding_model
                        customer.embedding_updated_at = datetime.now(UTC)
                        job.status, job.last_error_code = "completed", None
                        logger.info(
                            "verified_customer_embedding_created",
                            extra={
                                "customer_id": customer.id,
                                "customer_name": customer.name,
                                "owner_id": customer.owner_id,
                            }
                        )
                    except EmbeddingServiceError as error:
                        job.last_error_code = type(error).__name__
                        if job.attempts >= 5:
                            job.status = "failed"
                            logger.error(
                                "verified_customer_embedding_failed",
                                extra={
                                    "customer_id": customer.id,
                                    "error": str(error),
                                    "attempts": job.attempts,
                                }
                            )
                        else:
                            job.status = "pending"
                            job.available_at = now + timedelta(seconds=min(300, 2 ** job.attempts))
                
                else:
                    # Unknown entity type, mark as failed
                    logger.warning(
                        "unknown_embedding_entity_type",
                        extra={"entity_type": job.entity_type, "job_id": str(job.id)}
                    )
                    job.status = "failed"
                    job.last_error_code = "UnknownEntityType"
            
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
