"""
Logging Utilities
Structured logging for the application
"""
import logging
import sys
from typing import Optional


def setup_logger(
    name: str,
    level: int = logging.INFO,
    format_string: Optional[str] = None
) -> logging.Logger:
    """
    Setup a logger with consistent formatting
    
    Args:
        name: Logger name
        level: Logging level
        format_string: Optional custom format
    
    Returns:
        Configured logger
    """
    if format_string is None:
        format_string = (
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        )
    
    logger = logging.getLogger(name)
    logger.setLevel(level)
    
    # Console handler
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(level)
        formatter = logging.Formatter(format_string)
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    
    return logger


def log_api_request(logger: logging.Logger, method: str, path: str, user_id: Optional[int] = None):
    """Log API request"""
    user_info = f"user={user_id}" if user_id else "unauthenticated"
    logger.info(f"API Request: {method} {path} ({user_info})")


def log_api_response(logger: logging.Logger, status_code: int, duration_ms: float):
    """Log API response"""
    logger.info(f"API Response: {status_code} ({duration_ms:.2f}ms)")


def log_error(logger: logging.Logger, operation: str, error: Exception):
    """Log error with context"""
    logger.error(f"Error in {operation}: {type(error).__name__}: {str(error)}")
