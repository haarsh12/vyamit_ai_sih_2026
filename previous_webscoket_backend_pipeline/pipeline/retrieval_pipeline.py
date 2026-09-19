"""
Retrieval Pipeline - Vector Search and Context Retrieval
Handles item, customer, and analytics retrieval
"""
import json
import time
import logging
from typing import List, Dict, Any, Optional
from sqlalchemy import Engine, text
from sqlmodel import Session, select
from datetime import datetime, timedelta
from .config import config

logger = logging.getLogger(__name__)


class RetrievalPipeline:
    """Retrieves relevant context from database"""
    
    def __init__(self, engine: Engine):
        self.engine = engine
    
    def retrieve_items(
        self,
        query_embedding: List[float],
        user_id: int,
        shop_category: str,
        top_k: int = None,
        threshold: float = None
    ) -> List[Dict[str, Any]]:
        """
        Retrieve similar items using vector search
        
        Args:
            query_embedding: Query embedding vector
            user_id: User ID for filtering
            shop_category: Authenticated user's active inventory namespace
            top_k: Number of results (default from config)
            threshold: Similarity threshold (default from config)
        
        Returns:
            List of similar items with metadata
        """
        top_k = config.retrieval.item_top_k if top_k is None else top_k
        threshold = config.retrieval.item_similarity_threshold if threshold is None else threshold
        
        start = time.time()
        
        try:
            with Session(self.engine) as session:
                # Vector similarity search using cosine distance
                query = text("""
                    SELECT 
                        id,
                        master_id,
                        names,
                        category,
                        price,
                        unit,
                        1 - (embedding <=> :embedding) as similarity
                    FROM items
                    WHERE owner_id = :user_id
                        AND shop_category = :shop_category
                        AND embedding IS NOT NULL
                        AND (1 - (embedding <=> :embedding)) > :threshold
                    ORDER BY embedding <=> :embedding
                    LIMIT :top_k
                """)
                
                result = session.execute(
                    query,
                    {
                        "embedding": str(query_embedding),
                        "user_id": user_id,
                        "shop_category": shop_category,
                        "threshold": threshold,
                        "top_k": top_k
                    }
                )
                
                items = []
                for row in result:
                    items.append({
                        "id": row.id,
                        "master_id": row.master_id,
                        "names": row.names,
                        "category": row.category,
                        "price": row.price,
                        "unit": row.unit,
                        "similarity": float(row.similarity)
                    })
                
                duration = time.time() - start
                logger.info(
                    "Retrieved %s items in %.2fms user=%s scope=%s",
                    len(items),
                    duration * 1000,
                    user_id,
                    shop_category,
                )
                return items
                
        except Exception as e:
            logger.error(f"Item retrieval failed: {e}")
            return []
    
    def retrieve_customers(
        self,
        query_embedding: List[float],
        user_id: int,
        top_k: int = None,
        threshold: float = None
    ) -> List[Dict[str, Any]]:
        """
        Retrieve verified customer names and their newest linked bills.
        
        Args:
            query_embedding: Query embedding vector
            user_id: User ID for filtering
            top_k: Number of results (default from config)
            threshold: Similarity threshold (default from config)
        
        Returns:
            List of similar customers with purchase history
        """
        top_k = config.retrieval.customer_top_k if top_k is None else top_k
        # Customer voice queries often contain a full natural-language
        # sentence ("Rahul ka last bill batao"), so retain the nearest five
        # candidates instead of dropping a legitimate name on a hard cutoff.
        # The prompt clearly labels these as candidates and requires a name
        # match before answering from their history.
        _ = config.retrieval.customer_similarity_threshold if threshold is None else threshold
        
        start = time.time()
        
        try:
            with Session(self.engine) as session:
                query = text("""
                    SELECT 
                        id,
                        name,
                        1 - (embedding <=> :embedding) as similarity
                    FROM verified_customers
                    WHERE owner_id = :user_id
                        AND embedding IS NOT NULL
                    ORDER BY embedding <=> :embedding
                    LIMIT :top_k
                """)
                
                result = session.execute(
                    query,
                    {
                        "embedding": str(query_embedding),
                        "user_id": user_id,
                        "top_k": top_k
                    }
                )
                
                customers = []
                for row in result:
                    customers.append({
                        "id": row.id,
                        "name": row.name,
                        "similarity": float(row.similarity),
                        "bills": [],
                    })

                for customer in customers:
                    bills_query = text("""
                        SELECT id, total_amount, total_items, items_json, bill_date,
                               payment_method
                        FROM bills
                        WHERE owner_id = :user_id
                          AND verified_customer_id = :customer_id
                        ORDER BY bill_date DESC
                        LIMIT :bill_limit
                    """)
                    bill_rows = session.execute(
                        bills_query,
                        {
                            "user_id": user_id,
                            "customer_id": customer["id"],
                            "bill_limit": config.retrieval.max_bills_per_customer,
                        },
                    )
                    total_spent = 0.0
                    for bill in bill_rows:
                        try:
                            items = json.loads(bill.items_json)
                        except (TypeError, json.JSONDecodeError):
                            items = []
                        amount = float(bill.total_amount or 0)
                        total_spent += amount
                        customer["bills"].append(
                            {
                                "id": bill.id,
                                "amount": amount,
                                "total_items": int(bill.total_items or 0),
                                "items": items,
                                "date": bill.bill_date.isoformat() if bill.bill_date else None,
                                "payment_method": bill.payment_method or "cash",
                            }
                        )
                    customer["bill_count"] = len(customer["bills"])
                    customer["total_spent"] = total_spent
                
                duration = time.time() - start
                logger.info(f"Retrieved {len(customers)} customers in {duration*1000:.2f}ms")
                return customers
                
        except Exception as e:
            logger.error(f"Verified customer retrieval failed: {e}")
            return []
    
    def retrieve_analytics(
        self,
        user_id: int,
        shop_category: str,
        days: int = None
    ) -> Optional[Dict[str, Any]]:
        """
        Retrieve business analytics
        
        Args:
            user_id: User ID
            shop_category: Authenticated user's active category snapshot
            days: Number of days (default from config)
        
        Returns:
            Analytics summary dict or None
        """
        days = days or config.analytics.default_period_days
        start = time.time()
        
        try:
            with Session(self.engine) as session:
                cutoff_date = datetime.utcnow() - timedelta(days=days)
                
                # Total revenue and bill count
                revenue_query = text("""
                    SELECT 
                        COUNT(*) as bill_count,
                        COALESCE(SUM(total_amount), 0) as total_revenue,
                        COALESCE(AVG(total_amount), 0) as avg_bill_value
                    FROM bills
                    WHERE owner_id = :user_id
                        AND shop_category = :shop_category
                        AND bill_date >= :cutoff_date
                """)
                
                revenue_result = session.execute(
                    revenue_query,
                    {
                        "user_id": user_id,
                        "shop_category": shop_category,
                        "cutoff_date": cutoff_date,
                    }
                ).first()
                
                # Top selling items
                top_items_query = text("""
                    SELECT 
                        item_name,
                        item_category,
                        COUNT(*) as sale_count,
                        SUM(quantity) as total_quantity,
                        SUM(total_price) as total_revenue
                    FROM sale_items
                    WHERE owner_id = :user_id
                        AND shop_category = :shop_category
                        AND sale_date >= :cutoff_date
                    GROUP BY item_name, item_category
                    ORDER BY total_revenue DESC
                    LIMIT :top_count
                """)
                
                top_items_result = session.execute(
                    top_items_query,
                    {
                        "user_id": user_id,
                        "shop_category": shop_category,
                        "cutoff_date": cutoff_date,
                        "top_count": config.analytics.top_items_count
                    }
                ).all()
                
                analytics = {
                    "period_days": days,
                    "total_revenue": float(revenue_result.total_revenue),
                    "bill_count": revenue_result.bill_count,
                    "avg_bill_value": float(revenue_result.avg_bill_value),
                    "top_items": [
                        {
                            "name": item.item_name,
                            "category": item.item_category,
                            "sale_count": item.sale_count,
                            "total_quantity": float(item.total_quantity),
                            "total_revenue": float(item.total_revenue)
                        }
                        for item in top_items_result
                    ]
                }
                
                duration = time.time() - start
                logger.info(f"Retrieved analytics in {duration*1000:.2f}ms")
                return analytics
                
        except Exception as e:
            logger.error(f"Analytics retrieval failed: {e}")
            return None
    
    async def retrieve_all_parallel(
        self,
        query_embedding: List[float],
        user_id: int,
        shop_category: str,
        include_analytics: bool = True,
        include_customers: bool = True
    ) -> Dict[str, Any]:
        """
        Retrieve all context in parallel
        
        Args:
            query_embedding: Query embedding
            user_id: User ID
            shop_category: Active inventory namespace
            include_analytics: Include analytics context
            include_customers: Include customer context
        
        Returns:
            Dictionary with items, customers, analytics, and timings
        """
        import asyncio
        
        start = time.time()
        
        # Create tasks
        tasks = []
        task_map = {}
        
        # Items (always included)
        tasks.append(asyncio.to_thread(
            self.retrieve_items,
            query_embedding,
            user_id,
            shop_category,
        ))
        task_map[len(tasks)-1] = "items"
        
        # Customers (optional)
        if include_customers:
            tasks.append(asyncio.to_thread(
                self.retrieve_customers,
                query_embedding,
                user_id
            ))
            task_map[len(tasks)-1] = "customers"
        
        # Analytics (optional)
        if include_analytics:
            tasks.append(asyncio.to_thread(
                self.retrieve_analytics,
                user_id,
                shop_category,
            ))
            task_map[len(tasks)-1] = "analytics"
        
        # Execute in parallel
        results = await asyncio.gather(*tasks)
        
        # Map results
        output = {
            "items": [],
            "customers": [],
            "analytics": None,
            "timings": {
                "total_parallel": time.time() - start
            }
        }
        
        for idx, result in enumerate(results):
            key = task_map[idx]
            output[key] = result
        
        return output
