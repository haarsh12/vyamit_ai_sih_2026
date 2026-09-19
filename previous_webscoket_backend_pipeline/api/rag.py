"""
RAG Voice AI API - Intelligent Query Processing
Handles voice queries with context-aware responses
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select
from typing import Dict, Any
import logging
import time
from db.database import get_session, engine
from core.shop_categories import stored_category
from db.models import User
from db.schemas import VoiceQueryRequest, VoiceQueryResponse
from core.security import get_current_user
from pipeline.embedding_pipeline import embedding_pipeline
from pipeline.retrieval_pipeline import RetrievalPipeline
from pipeline.prompt_pipeline import PromptPipeline
from pipeline.llm_pipeline import llm_pipeline

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/query", response_model=Dict)
async def rag_query(
    request: VoiceQueryRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """
    Process voice query with RAG pipeline
    
    Flow:
    1. Generate query embedding
    2. Retrieve relevant context (items, analytics, customers)
    3. Build contextual prompt
    4. Get LLM response
    5. Return structured response
    """
    start_time = time.time()
    
    try:
        logger.info(f"RAG query from user {user_id}: {request.query[:100]}")
        
        # Get user info
        user = session.get(User, user_id)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        shop_category = stored_category(user.shop_category)
        
        # Step 1: Generate embedding
        embedding_start = time.time()
        query_embedding, _ = embedding_pipeline.generate_query_embedding(request.query)
        embedding_time = time.time() - embedding_start
        
        # Step 2: Retrieve context
        retrieval_start = time.time()
        retrieval = RetrievalPipeline(engine)
        
        context = await retrieval.retrieve_all_parallel(
            query_embedding=query_embedding,
            user_id=user_id,
            shop_category=shop_category,
            include_analytics=request.include_analytics,
            # Verified customer names and linked bills are owner-scoped, not
            # category-scoped, so a merchant can ask about a customer's
            # history across their shop.
            include_customers=request.include_customers,
        )
        
        retrieval_time = time.time() - retrieval_start
        
        logger.info(
            f"Retrieved: {len(context['items'])} items, "
            f"{len(context.get('customers', []))} customers, "
            f"analytics={'yes' if context.get('analytics') else 'no'}"
        )
        
        # Step 3: Build prompt
        prompt_start = time.time()
        prompt_builder = PromptPipeline()
        
        prompt = prompt_builder.build_rag_prompt(
            user_query=request.query,
            items=context['items'],
            analytics=context.get('analytics'),
            customers=context.get('customers', []),
            shop_category=shop_category
        )
        
        prompt_time = time.time() - prompt_start
        
        # Step 4: Get LLM response
        llm_start = time.time()
        response, llm_duration, model_used = llm_pipeline.invoke(prompt)
        llm_time = time.time() - llm_start
        
        # Validate response
        if not llm_pipeline.validate_response(response):
            logger.warning("Invalid LLM response, using fallback")
            response = {
                "type": "ERROR",
                "items": [],
                "msg": "Unable to process request. Please try again.",
                "should_stop": False
            }
        
        total_time = time.time() - start_time
        
        logger.info(
            f"Query processed in {total_time:.2f}s "
            f"(embed:{embedding_time:.2f}s, retrieve:{retrieval_time:.2f}s, "
            f"llm:{llm_time:.2f}s, model:{model_used})"
        )
        
        # Build response with metadata
        return {
            **response,
            "metadata": {
                "model_used": model_used,
                "timings": {
                    "embedding": round(embedding_time, 3),
                    "retrieval": round(retrieval_time, 3),
                    "prompt_building": round(prompt_time, 3),
                    "llm_execution": round(llm_duration, 3),
                    "total": round(total_time, 3)
                },
                "context": {
                    "items_count": len(context['items']),
                    "customers_count": len(context.get('customers', [])),
                    "analytics_included": bool(context.get('analytics'))
                }
            }
        }
        
    except HTTPException:
        raise
    except Exception:
        logger.exception("RAG query failed for user=%s", user_id)
        return {
            "type": "ERROR",
            "items": [],
            "msg": "Sorry, I encountered an error processing your request. Please try again.",
            "should_stop": False,
            "metadata": {
                "timings": {
                    "total": round(time.time() - start_time, 3)
                }
            }
        }


@router.post("/query-simple")
async def rag_query_simple(
    request: VoiceQueryRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """
    Simplified RAG query (faster, less context)
    Good for simple billing requests
    """
    start_time = time.time()
    
    try:
        logger.info(f"Simple RAG query from user {user_id}")
        
        # Get user info
        user = session.get(User, user_id)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Generate embedding
        query_embedding, _ = embedding_pipeline.generate_query_embedding(request.query)
        
        # Retrieve only items
        retrieval = RetrievalPipeline(engine)
        items = retrieval.retrieve_items(
            query_embedding=query_embedding,
            user_id=user_id,
            shop_category=stored_category(user.shop_category),
            top_k=5
        )
        
        # Build simple prompt
        prompt_builder = PromptPipeline()
        prompt = prompt_builder.build_simple_prompt(
            user_query=request.query,
            items=items,
            shop_category=stored_category(user.shop_category)
        )
        
        # Get response
        response, duration, model_used = llm_pipeline.invoke(prompt)
        
        total_time = time.time() - start_time
        
        logger.info(f"Simple query processed in {total_time:.2f}s")
        
        return {
            **response,
            "metadata": {
                "model_used": model_used,
                "timings": {
                    "total": round(total_time, 3)
                },
                "mode": "simple"
            }
        }
        
    except Exception as e:
        logger.error(f"Simple RAG query failed: {e}")
        return {
            "type": "ERROR",
            "items": [],
            "msg": "Unable to process request.",
            "should_stop": False
        }


@router.get("/status")
def get_rag_status():
    """Get RAG pipeline status"""
    try:
        from pipeline.embedding_pipeline import embedding_pipeline
        from pipeline.config import config
        
        embedding_info = embedding_pipeline.get_info()
        
        return {
            "status": "operational",
            "embedding": {
                "provider": embedding_info.get("provider"),
                "model": embedding_info.get("model"),
                "dimension": embedding_info.get("dimension"),
                "initialized": embedding_info.get("initialized")
            },
            "llm": {
                "primary": config.llm.primary_model,
                "fallback": config.llm.fallback_models
            },
            "config": {
                "retrieval_top_k": config.retrieval.item_top_k,
                "parallel_retrieval": config.enable_parallel_retrieval
            }
        }
        
    except Exception as e:
        logger.error(f"Status check failed: {e}")
        return {
            "status": "error",
            "error": str(e)
        }


from typing import Dict

