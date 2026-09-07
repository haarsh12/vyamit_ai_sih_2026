"""Hybrid customer search with cascade fallback: exact → fuzzy → semantic."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import VerifiedCustomer
from app.db.tenant import TenantContext
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.retrieval.embeddings import VertexEmbeddingService


logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class CustomerMatch:
    """A single search result with confidence score and match method."""
    customer: VerifiedCustomer
    score: float
    method: str  # "exact", "fuzzy", or "semantic"

    def to_tool_payload(self) -> dict[str, object]:
        """Format for agent tool response."""
        return {
            "id": self.customer.id,
            "name": self.customer.name,
            "phone_number": self.customer.phone_number,
            "total_bills": self.customer.total_bills,
            "total_spent": float(self.customer.total_spent),
            "last_purchase_date": (
                self.customer.last_purchase_date.isoformat()
                if self.customer.last_purchase_date
                else None
            ),
            "match_score": round(self.score, 3),
            "match_method": self.method,
        }


class CustomerSearchService:
    """
    Hybrid customer search with multi-stage cascade:
    1. Exact name match (case-insensitive)
    2. Fuzzy substring match
    3. Semantic pgvector search (fallback with timeout)
    """

    def __init__(self, embeddings: VertexEmbeddingService | None = None) -> None:
        self.embeddings = embeddings

    async def search(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        query: str,
        *,
        limit: int = 5,
    ) -> list[CustomerMatch]:
        """
        Search verified customers using cascading strategy.
        
        Returns up to `limit` matches, prioritizing exact matches over fuzzy over semantic.
        """
        repository = VerifiedCustomerRepository(session)
        safe_limit = min(max(limit, 1), 20)
        
        clean_query = query.strip()
        if not clean_query or len(clean_query) < 2:
            return []
        
        query_lower = clean_query.lower()
        
        # 1. Exact Name Match (case-insensitive)
        exact_match = await repository.find_by_exact_name(tenant, clean_query)
        if exact_match:
            logger.info(
                "customer_search_exact_match",
                extra={
                    "query": query,
                    "customer_id": exact_match.id,
                    "customer_name": exact_match.name,
                    "owner_id": tenant.owner_id,
                }
            )
            return [CustomerMatch(exact_match, 1.0, "exact")]
        
        # 2. Fuzzy Substring Match
        fuzzy_matches = await repository.find_by_name_pattern(tenant, clean_query, limit=safe_limit)
        if fuzzy_matches:
            logger.info(
                "customer_search_fuzzy_match",
                extra={
                    "query": query,
                    "matches_count": len(fuzzy_matches),
                    "owner_id": tenant.owner_id,
                }
            )
            # Assign scores based on position of match (earlier = higher score)
            results = []
            for customer in fuzzy_matches:
                # Simple scoring: substring at start gets higher score
                customer_name_lower = customer.name.lower()
                if customer_name_lower.startswith(query_lower):
                    score = 0.95
                elif query_lower in customer_name_lower:
                    score = 0.85
                else:
                    score = 0.75
                results.append(CustomerMatch(customer, score, "fuzzy"))
            
            return results[:safe_limit]
        
        # 3. Semantic pgvector Search (with timeout for safety)
        if self.embeddings is None:
            self.embeddings = VertexEmbeddingService()
        
        try:
            query_embedding = await asyncio.wait_for(
                self.embeddings.embed_query(clean_query),
                timeout=1.5
            )
            
            semantic_results = await repository.search_by_embedding(
                tenant,
                query_embedding,
                limit=safe_limit,
                min_score=0.6,  # Only return reasonably similar names
            )
            
            if semantic_results:
                logger.info(
                    "customer_search_semantic_match",
                    extra={
                        "query": query,
                        "matches_count": len(semantic_results),
                        "owner_id": tenant.owner_id,
                        "top_score": semantic_results[0][1] if semantic_results else 0,
                    }
                )
                return [
                    CustomerMatch(customer, score, "semantic")
                    for customer, score in semantic_results
                ]
        except asyncio.TimeoutError:
            logger.warning(
                "customer_search_semantic_timeout",
                extra={"query": query, "owner_id": tenant.owner_id}
            )
        except Exception as error:
            logger.exception(
                "customer_search_semantic_error",
                extra={"query": query, "owner_id": tenant.owner_id, "error": str(error)}
            )
        
        # No matches found
        logger.info(
            "customer_search_no_match",
            extra={"query": query, "owner_id": tenant.owner_id}
        )
        return []

    async def find_or_suggest(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        name: str,
    ) -> tuple[VerifiedCustomer | None, list[CustomerMatch]]:
        """
        Find exact match or return suggestions.
        
        Returns:
            - (customer, []) if exact match found
            - (None, [suggestions]) if similar names exist
            - (None, []) if no matches
        """
        repository = VerifiedCustomerRepository(session)
        
        # Try exact match first
        exact_match = await repository.find_by_exact_name(tenant, name)
        if exact_match:
            return exact_match, []
        
        # Return fuzzy/semantic suggestions
        suggestions = await self.search(session, tenant, name, limit=3)
        return None, suggestions


customer_search_service = CustomerSearchService()
