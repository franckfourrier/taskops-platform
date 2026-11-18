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

### 2. Image Docker au-dessus de l'objectif de 200 Mo
- **Symptôme :** image décompressée ≈ 210 Mo (65,7 Mo compressée) ; `docker history` montre une couche venv de 74,6 Mo.
- **Cause :** le venv embarquait `pip` (inutile à l'exécution) et les fichiers `.pyc` précompilés à l'installation.
- **Réparation :** `pip install --no-compile` puis `pip uninstall -y pip` dans l'étape builder.
- **Résultat :** venv 74,6 → 43 Mo (−42 %), image compressée 65,7 → 55,7 Mo, image décompressée ≈ 177 Mo.
- **Leçon :** mesurer couche par couche avec `docker history` avant d'optimiser ; avec Docker 29 (magasin containerd), distinguer CONTENT SIZE (compressé) et DISK USAGE (compressé + décompressé).

### 3. Le conteneur seul plante au démarrage (non-root + SQLite)
- **Symptôme :** `docker run` seul → `Connection reset by peer` ; logs : `sqlite3.OperationalError: unable to open database file` puis `Application startup failed`.
- **Cause :** sans `DATABASE_URL`, l'API crée `./tasks.db` dans `/srv`, qui appartient à root ; l'utilisateur non-root `app` n'a pas le droit d'y écrire. Invisible avec `make up` (PostgreSQL).
- **Réparation :** dossier `/srv/data` appartenant à `app` + `ENV DATABASE_URL=sqlite:////srv/data/tasks.db` par défaut.
- **Prévention :** ajout d'un smoke test en CI (l'image doit répondre sur `/health` en moins de 30 s), qui aurait bloqué la v0.1.0.
- **Leçon :** passer en non-root a des effets de bord sur les droits d'écriture ; tester l'image telle qu'elle sera lancée, pas seulement le code.

## Projet 2 — AWS / Terraform

### 4. Clé d'accès AWS exposée par erreur
- **Symptôme :** la clé secrète de l'utilisateur IAM `taskops-admin` a été copiée en clair hors de la machine (message de discussion).
- **Cause :** copier-coller de la sortie de `aws configure` sans vérifier son contenu.
- **Réparation (rotation immédiate, sans afficher le nouveau secret) :** `aws iam create-access-key` → `aws configure set` → `aws sts get-caller-identity` pour vérifier → `aws iam delete-access-key` sur l'ancienne clé.
- **Leçon :** tout secret exposé est considéré comme compromis, même brièvement ; ne jamais coller de sortie sans relecture ; pour la CI, aucune clé longue durée → OIDC (droits temporaires).
