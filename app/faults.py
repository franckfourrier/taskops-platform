"""Injection de pannes contrôlée (tests de résilience et démonstration du canary).

FAULT_RATE (0 à 1, défaut 0) : part des requêtes métier qui répondent 500.
Désactivé par défaut ; /health et /metrics ne sont jamais concernés,
pour que la panne soit visible dans les métriques sans tuer les pods.
"""

import os
import random
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from fastapi.responses import JSONResponse

_EXEMPTS = {"/health", "/metrics"}


def _fault_rate() -> float:
    try:
        return min(max(float(os.environ.get("FAULT_RATE", "0")), 0.0), 1.0)
    except ValueError:
        return 0.0


async def fault_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    rate = _fault_rate()
    if rate > 0 and request.url.path not in _EXEMPTS and random.random() < rate:  # noqa: S311 (pas un usage cryptographique)
        return JSONResponse(status_code=500, content={"detail": "panne injectée (FAULT_RATE)"})
    return await call_next(request)
