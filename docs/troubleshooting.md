# Ce qui a cassé et comment je l'ai réparé

Journal des vraies pannes rencontrées. Format : symptôme → cause → réparation → leçon.

## Projet 1 — CI/CD

### 1. Connection reset juste après `make up`
- **Symptôme :** `curl: (56) Recv failure: Connection reset by peer` sur `/health`, lancé juste après `docker compose up -d`.
- **Cause :** `up -d` rend la main dès que le conteneur est *démarré*, pas quand l'application est *prête* : uvicorn n'écoutait pas encore sur le port 8000.
- **Réparation :** attendre la disponibilité réelle avant d'envoyer des requêtes :
  `until curl -sf localhost:8000/health; do sleep 1; done`
- **Leçon :** « démarré » ≠ « prêt ». Même logique que `depends_on: condition: service_healthy` (Compose) et la `readinessProbe` (Kubernetes, projet 3).

<!-- Pannes classiques à provoquer volontairement pour s'entraîner :
- retirer le bloc `permissions: packages: write` -> push GHCR refusé (denied: permission_denied)
- lancer uvicorn avec --host 127.0.0.1 -> conteneur "healthy" impossible à joindre depuis l'hôte
- remplacer python:3.12-slim par python:3.12 -> taille de l'image x5
- casser un test dans une PR -> merge bloqué par la protection de branche
-->
