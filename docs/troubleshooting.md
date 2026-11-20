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

### 5. GitHub Actions refusé par AWS (OIDC)
- **Symptôme :** `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` (12 tentatives), alors que le rôle existe.
- **Diagnostic :** étape temporaire affichant le `sub` du jeton OIDC : `repo:franckfourrier@251311851/taskops-platform@1462627752:pull_request`.
- **Cause :** GitHub inclut désormais les identifiants numériques immuables du propriétaire et du dépôt dans le `sub` ; la règle de confiance IAM attendait l'ancien format `repo:franckfourrier/taskops-platform:...` (`StringEquals` exact).
- **Réparation :** règle de confiance mise à jour avec le nouveau format.
- **Leçon :** ne jamais deviner une identité fédérée — l'afficher et comparer. Le nouveau format protège contre la recréation d'un dépôt homonyme par un tiers.

## Projet 3 — Kubernetes

### 6. Scheduler et controller-manager redémarrent en boucle (Kind)
- **Symptôme :** `kube-scheduler` et `kube-controller-manager` en `0/1` avec redémarrages ; logs : `Failed to renew lease … context deadline exceeded` puis `Leaderelection lost`.
- **Diagnostic :** etcd lent (`apply request took too long` jusqu'à 1,7 s pour 100 ms attendus) ; `ops` est une VM VMware sur disque virtuel lent ; forte charge pendant le démarrage.
- **Cause :** l'API répond trop lentement pour que les composants renouvellent leur bail de leader (délai par défaut 10 s) ; ils s'arrêtent par sécurité.
- **Réparation (cluster de DEV uniquement) :** `kubeadmConfigPatches` dans `kind-config.yaml` : etcd `unsafe-no-fsync`, baux de leader 60 s / renouvellement 40 s → 0 redémarrage.
- **Leçon :** les « redémarrages » d'un composant du plan de contrôle se lisent dans `logs --previous` ; la cause est souvent l'infrastructure (disque, CPU), pas Kubernetes. En production : disque SSD/NVMe dédié pour etcd, jamais `unsafe-no-fsync`.

### 7. L'init container reste bloqué en `Init:0/1`
- **Symptôme :** après `helm install`, pods de l'API en `Init:0/1` pendant 5 min, `helm --wait` en échec (`context deadline exceeded`), Traefik répond `no available server` ; pourtant `postgres-0` est `Running`.
- **Diagnostic :** `kubectl logs deploy/taskops-api -c attente-postgres` → `postgres:5432 - no attempt` en boucle.
- **Cause :** l'init container tourne en non-root (UID 10001, inexistant dans l'image postgres) ; sans `-U`, `pg_isready` ne peut pas déterminer l'utilisateur et n'essaie même pas de se connecter (code retour 3).
- **Réparation :** `pg_isready -h postgres -p 5432 -U tasks -d tasks`.
- **Leçon :** lire les logs du conteneur *init* (`-c <nom>`), pas seulement ceux de l'application ; « no attempt » ≠ « no response » (paramètres invalides vs serveur injoignable).

### 8. Argo CD bloqué en « Progressing » et mise à jour de Traefik impossible
- **Symptôme 1 :** application Argo CD `Synced` mais `Progressing` en permanence ; l'Ingress n'a pas d'`ADDRESS`.
- **Cause 1 :** Argo CD ne déclare un Ingress sain que si son statut contient une adresse ; sur Kind, Traefik a un Service `ClusterIP` (accès par les ports de l'hôte) et ne publie rien.
- **Réparation 1 :** `providers.kubernetesIngress.ingressEndpoint.ip` (publishedService désactivé) → Ingress `127.0.0.1`, application `Healthy`.
- **Symptôme 2 :** `helm upgrade traefik` → `Deployment not ready … context deadline exceeded` ; nouveau pod `Pending`, ancien pod `Running`.
- **Cause 2 :** mise à jour progressive par défaut (`maxSurge: 1`, `maxUnavailable: 0`) : le nouveau pod attend le port 80/443 de l'hôte, encore occupé par l'ancien.
- **Réparation 2 :** `updateStrategy.rollingUpdate` : `maxSurge: 0`, `maxUnavailable: 1`.
- **Leçon :** un pod qui utilise `hostPort` ne peut pas être doublé sur un même nœud ; « Healthy » pour Argo CD dépend de règles propres à chaque type de ressource.

## Projet 4 — Monitoring

### 9. Installation de kube-prometheus-stack : `helm --wait` dépasse 10 minutes
- **Symptôme :** `Error: resource Deployment/monitoring/kps-grafana not ready … context deadline exceeded` ; release Helm en échec alors que Prometheus et Alertmanager tournent. kube-state-metrics et Grafana redémarrent 1 à 2 fois (`Liveness probe failed: … 503`).
- **Diagnostic :** `kubectl describe pod` → `Pulling image` : chaque image met 1 à 2 min à se télécharger (connexion lente), Grafana 13 étant la plus lourde ; pendant ce temps l'API Kubernetes (etcd lent, cf. n° 6) répond lentement.
- **Cause :** le délai de `--wait` couvre aussi le téléchargement des images ; les sondes de vie ont expiré pendant la surcharge de démarrage.
- **Réparation :** attendre la fin des téléchargements (`kubectl wait --for=condition=Ready`), puis relancer le même `helm upgrade --install` → révision 2 `deployed` en quelques secondes (images en cache). Pods stables ensuite.
- **Leçon :** une release Helm « failed » ne veut pas dire des ressources cassées : regarder les pods avant de désinstaller. Sur un lien lent, pré-charger les images (`docker pull` + `kind load docker-image`) ou allonger `--timeout`.

### 10. Alerte `KubeAPIErrorBudgetBurn` permanente sur Kind
- **Symptôme :** dès l'installation, `KubeAPIErrorBudgetBurn` (warning) reste `firing`, sans aucun impact visible sur l'application.
- **Cause :** cette règle mesure le « budget d'erreur » de l'API Kubernetes (taux d'erreurs et lenteur par rapport à un objectif de qualité de service). Sur la VM, etcd est lent (n° 6) : l'API dépasse régulièrement ses objectifs de latence.
- **Réparation (DEV uniquement) :** alerte conservée dans Prometheus (visible dans Grafana) mais **non notifiée** sur Telegram (route `null` dans Alertmanager), pour ne pas habituer à ignorer les notifications.
- **Leçon :** une alerte qui sonne en permanence finit ignorée (fatigue d'alerte) ; on traite la cause ou on la sort explicitement et de façon documentée. En production : disque rapide pour etcd, et cette alerte doit être notifiée.

### 11. Notification Telegram avec « Namespace : » vide
- **Symptôme :** le message 🔥 `TaskOpsAPIDown` arrive bien, mais le champ namespace est vide.
- **Cause :** l'expression `(sum(up{…}) or vector(0)) == 0` agrège les séries : `sum()` sans `by` supprime tous les labels, dont `namespace`.
- **Réparation :** label statique `namespace: taskops` ajouté dans la règle (`labels:` de la PrometheusRule).
- **Leçon :** les labels d'une alerte viennent du résultat de l'expression ; après une agrégation, il faut les rajouter explicitement (ou agréger `by (namespace)`). Tester le message réel de bout en bout, pas seulement le déclenchement.

### 12. `/metrics` accessible publiquement
- **Symptôme :** `curl http://10.10.10.13/metrics` renvoie les métriques internes de l'API depuis l'extérieur du cluster.
- **Cause :** l'Ingress publiait tout le préfixe `/`.
- **Réparation :** liste blanche de chemins dans le chart (`ingress.paths` : `/tasks`, `/health`, `/docs`, `/openapi.json`) → `/metrics` répond 404 via Traefik ; Prometheus le lit toujours en interne via le Service (2 cibles `up`).
- **Leçon :** les métriques révèlent l'architecture et les volumes : on publie ce qui est nécessaire (liste blanche), pas tout par défaut.
