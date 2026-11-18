IMAGE ?= taskops-api:dev
COMPOSE = docker compose -f docker/docker-compose.yml

.PHONY: install lint fmt test build scan run up down logs

install:          ## Crée le venv et installe les dépendances de dev
	python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt

lint:             ## Lint + vérification du formatage
	.venv/bin/ruff check . && .venv/bin/ruff format --check .

fmt:              ## Formate le code
	.venv/bin/ruff format . && .venv/bin/ruff check --fix .

test:             ## Lance les tests (SQLite par défaut)
	.venv/bin/pytest -v

build:            ## Construit l'image Docker
	docker build -f docker/Dockerfile -t $(IMAGE) .

scan: build       ## Scanne l'image avec Trivy (installé localement)
	trivy image --severity HIGH,CRITICAL $(IMAGE)

run: build        ## Lance l'API seule (SQLite dans le conteneur)
	docker run --rm -p 8000:8000 $(IMAGE)

up:               ## API + PostgreSQL via docker compose
	$(COMPOSE) up --build -d

down:             ## Arrête la stack (garde les données)
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f api
