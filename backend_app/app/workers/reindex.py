"""Server-only command to enqueue a controlled inventory embedding backfill."""

from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime

from sqlalchemy import select

from app.db.models import EmbeddingJob, Item
from app.db.session import get_session_factory
from app.repositories.inventory import item_embedding_source_hash


async def enqueue_item_reindex(*, owner_id: int | None, force: bool) -> int:
    """Queue item embeddings without calling Vertex or exposing an HTTP endpoint."""

    factory = get_session_factory()
    if factory is None:
        raise RuntimeError("DATABASE_URL is required for a reindex job.")

    async with factory() as session:
        statement = select(Item)
        if owner_id is not None:
            statement = statement.where(Item.owner_id == owner_id)
        items = (await session.scalars(statement)).all()
        now = datetime.now(UTC)
        for item in items:
            if force:
                item.embedding = None
                item.embedding_source_hash = None
                item.embedding_model = None
                item.embedding_updated_at = None
            session.add(
                EmbeddingJob(
                    entity_type="item",
                    entity_id=item.id,
                    owner_id=item.owner_id,
                    operation="upsert",
                    source_hash=item_embedding_source_hash(item),
                    available_at=now,
                )
            )
        await session.commit()
        return len(items)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Queue a server-side inventory embedding reindex.")
    parser.add_argument("--owner-id", type=int, help="Only reindex one owner; omit for all owners.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Clear existing vectors first; use after an approved embedding-model migration.",
    )
    return parser.parse_args()


async def main() -> None:
    args = _arguments()
    count = await enqueue_item_reindex(owner_id=args.owner_id, force=args.force)
    print(f"Queued {count} inventory embedding jobs.")


if __name__ == "__main__":
    asyncio.run(main())
