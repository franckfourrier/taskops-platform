"""Métriques Prometheus de l'API (exposées sur /metrics).

Méthode RED : Rate (débit), Errors (erreurs), Duration (latence).
Le label `route` utilise le modèle de route (/tasks/{id}) et non l'URL réelle,
pour garder un nombre de séries limité (cardinalité maîtrisée).
"""

import time
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

HTTP_REQUESTS = Counter(
    "taskops_http_requests_total",
    "Nombre de requêtes HTTP traitées",
    ["method", "route", "status"],
)
HTTP_DURATION = Histogram(
    "taskops_http_request_duration_seconds",
    "Durée de traitement des requêtes HTTP",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
TASKS_CREATED = Counter("taskops_tasks_created_total", "Nombre de tâches créées")

# Routes non mesurées : le scraping et les sondes Kubernetes fausseraient les chiffres
_EXCLUDED = {"/metrics", "/health"}


async def metrics_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        path = getattr(route, "path", "inconnue")
        if path not in _EXCLUDED:
            HTTP_REQUESTS.labels(request.method, path, str(status)).inc()
            HTTP_DURATION.labels(request.method, path).observe(time.perf_counter() - start)


def metrics_endpoint() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
