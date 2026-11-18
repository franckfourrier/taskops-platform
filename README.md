# TaskOps — taskops-platform

[![CI](https://github.com/franckfourrier/taskops-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/franckfourrier/taskops-platform/actions/workflows/ci.yml)

Plateforme DevOps de bout en bout autour d'une API de gestion de tâches (FastAPI + PostgreSQL) :
CI/CD sécurisée, infrastructure AWS en Terraform, Kubernetes, monitoring Prometheus/Grafana
et architecture haute disponibilité.

## Avancement

| # | Projet | Statut |
|---|--------|--------|
| 1 | Pipeline CI/CD (GitHub Actions, Docker, Trivy, GHCR) | 🚧 en cours |
| 2 | Infrastructure AWS avec Terraform | ⏳ |
| 3 | Déploiement Kubernetes (Kind, Helm, HPA, Argo CD) | ⏳ |
| 4 | Monitoring Prometheus / Grafana / Alertmanager | ⏳ |
| 5 | Architecture haute disponibilité (CloudNativePG, Argo Rollouts, NetworkPolicies) | ⏳ |

## L'application

| Route | Rôle |
|-------|------|
| `GET /health` | Health check (`{"status": "ok"}`) utilisé par Docker, Kubernetes et le monitoring |
| `GET /tasks` | Liste les tâches |
| `POST /tasks` | Crée une tâche (`{"title": "...", "done": false}`) |

Configuration : variable `DATABASE_URL` (PostgreSQL en compose/CI/K8s, SQLite par défaut en dev).

## Projet 1 — Pipeline CI/CD

### Stack et choix

| Outil | Rôle | Pourquoi |
|-------|------|----------|
| GitHub Actions | CI/CD | Intégré au dépôt, gratuit pour un dépôt public |
| pytest + PostgreSQL (service CI) | Tests | Tests contre une vraie base, comme en prod |
| Ruff | Lint + format (+ règles de sécurité `S`) | Très rapide, remplace flake8/isort/black |
| Docker multi-étapes, `python:3.12-slim` | Image | Image légère, non-root, avec HEALTHCHECK |
| Trivy | Scan de vulnérabilités | Bloque le pipeline sur une faille CRITICAL corrigeable |
| GHCR | Registre | Authentification par `GITHUB_TOKEN`, aucun secret à gérer |

### Pipeline

```
push / PR ──► lint (ruff) ──► tests (pytest + Postgres) ──► build image ──► scan Trivy ──► push GHCR
                                                                                (main et tags v* uniquement)
```

Tags produits : SHA complet du commit, `latest` sur `main`, et `1.2.3` / `1.2` sur une release `v1.2.3`.

### Sécurité

- Image exécutée en **non-root** (UID 10001), mises à jour OS appliquées au build.
- Aucun secret dans le code : `GITHUB_TOKEN` éphémère pour GHCR.
- Permissions du workflow au **moindre privilège** (`contents: read`, `packages: write` seulement pour le job de push).
- Actions GitHub **épinglées par SHA** de commit (protection contre la compromission d'un tag).
- Rapport Trivy publié comme artefact à chaque exécution.

### Lancer en local

```bash
make install && make lint && make test   # venv + lint + tests
make up                                  # API + PostgreSQL via docker compose
curl localhost:8000/health
curl -X POST localhost:8000/tasks -H 'Content-Type: application/json' -d '{"title":"test"}'
curl localhost:8000/tasks
make down
```

## Ce qui a cassé et comment je l'ai réparé

Voir [docs/troubleshooting.md](docs/troubleshooting.md).

## Améliorations prévues

- Migrations de schéma avec Alembic (au lieu de `create_all`).
- Signature des images (cosign) et SBOM.
