"""Small dependency-free request limits for a single API process."""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque
from typing import Deque, Hashable

from fastapi import HTTPException, status


class SlidingWindowRateLimiter:
    """Process-local limiter; production multi-worker deployments need shared storage."""

    def __init__(self, max_requests: int, window_seconds: int) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._events: dict[Hashable, Deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, *parts: str) -> None:
        key = tuple(str(part) for part in parts)
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
