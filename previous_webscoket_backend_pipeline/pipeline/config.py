"""
Pipeline Configuration
Centralized configuration for RAG pipeline (v1.1)
"""
import os
from pydantic import BaseModel
from typing import Optional


class EmbeddingConfig(BaseModel):
    """Embedding configuration"""
    dimension: int = 768
    model: str = "gemini-embedding-001"
    provider: str = "gemini"


class RetrievalConfig(BaseModel):
    """Retrieval configuration"""
    # Item search
    item_top_k: int = 5
    item_similarity_threshold: float = 0.3
    
    # Customer search
    customer_top_k: int = 5
    customer_similarity_threshold: float = 0.4
    
    # History limits
    max_bills_per_customer: int = 5
    history_days: int = 90


class LLMConfig(BaseModel):
    """LLM configuration"""
    # Primary model (Mistral) - Use free tier by default
    primary_model: str = "mistral-small-latest"  # Free tier model
    primary_temperature: float = 0.1
    primary_max_tokens: int = 500
    
    # Fallback models (Gemini) - Use base names without -latest for v1beta API
    fallback_models: list[str] = [
        "gemini-1.5-flash",
        "gemini-1.5-pro"
    ]
    fallback_temperature: float = 0.1
    fallback_max_tokens: int = 500
    
    # Timeout
    timeout_seconds: int = 30


class AnalyticsConfig(BaseModel):
    """Analytics configuration"""
    default_period_days: int = 30
    top_items_count: int = 10
    low_stock_threshold: float = 10.0


class LoggingConfig(BaseModel):
    """Logging configuration"""
    enabled: bool = True
    log_embeddings: bool = True
    log_retrieval: bool = True
    log_llm: bool = True
    log_latency: bool = True
    max_context_preview: int = 200


class RAGPipelineConfig(BaseModel):
    """Master RAG pipeline configuration"""
    embedding: EmbeddingConfig = EmbeddingConfig()
    retrieval: RetrievalConfig = RetrievalConfig()
    llm: LLMConfig = LLMConfig()
    analytics: AnalyticsConfig = AnalyticsConfig()
    logging: LoggingConfig = LoggingConfig()
    
    # Features
    enable_parallel_retrieval: bool = True
    enable_customer_context: bool = True
    enable_analytics_context: bool = True


# Global config instance
config = RAGPipelineConfig()


# Environment overrides
def load_config_from_env():
    """Load configuration overrides from environment variables"""
    if os.getenv("RETRIEVAL_TOP_K"):
        config.retrieval.item_top_k = int(os.getenv("RETRIEVAL_TOP_K"))
    
    if os.getenv("LLM_TEMPERATURE"):
        config.llm.primary_temperature = float(os.getenv("LLM_TEMPERATURE"))
    
    if os.getenv("ANALYTICS_DAYS"):
        config.analytics.default_period_days = int(os.getenv("ANALYTICS_DAYS"))


# Load on import
load_config_from_env()
