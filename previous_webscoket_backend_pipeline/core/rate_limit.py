"""Small dependency-free rate limits for security-sensitive entry points.

The limiter is process-local by design.  It protects single-instance and
development deployments; production multi-worker deployments should replace
it with a shared Redis-backed limiter at the infrastructure boundary.
"""

from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque
from typing import Deque, Dict, Hashable, Tuple

from fastapi import HTTPException, status


class SlidingWindowRateLimiter:
    def __init__(self, max_requests: int, window_seconds: int) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._events: Dict[Hashable, Deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, *parts: str) -> None:
        key: Tuple[str, ...] = tuple(str(part) for part in parts)
        now = time.monotonic()
        with self._lock:
            events = self._events[key]
            cutoff = now - self.window_seconds
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= self.max_requests:
                retry_after = max(1, int(events[0] + self.window_seconds - now))
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Too many requests. Please wait before trying again.",
                    headers={"Retry-After": str(retry_after)},
                )
            events.append(now)


otp_rate_limiter = SlidingWindowRateLimiter(
    max_requests=int(os.getenv("OTP_RATE_LIMIT", "3")),
    window_seconds=int(os.getenv("OTP_RATE_LIMIT_WINDOW_SECONDS", "300")),
)
