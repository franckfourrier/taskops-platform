# TaskOps — taskops-platform

[![CI](https://github.com/franckfourrier/taskops-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/franckfourrier/taskops-platform/actions/workflows/ci.yml)
[![Terraform](https://github.com/franckfourrier/taskops-platform/actions/workflows/terraform.yml/badge.svg)](https://github.com/franckfourrier/taskops-platform/actions/workflows/terraform.yml)
[![Détection de dérive](https://github.com/franckfourrier/taskops-platform/actions/workflows/drift.yml/badge.svg)](https://github.com/franckfourrier/taskops-platform/actions/workflows/drift.yml)
[![Kubernetes](https://github.com/franckfourrier/taskops-platform/actions/workflows/k8s.yml/badge.svg)](https://github.com/franckfourrier/taskops-platform/actions/workflows/k8s.yml)

Plateforme DevOps de bout en bout autour d'une API de gestion de tâches (FastAPI + PostgreSQL) :
CI/CD sécurisée, infrastructure AWS en Terraform pilotée par GitHub Actions (OIDC), Kubernetes
en GitOps (Helm + Argo CD), monitoring Prometheus/Grafana et architecture haute disponibilité.

## Avancement

| # | Projet | Statut |
|---|--------|--------|
| 1 | Pipeline CI/CD (GitHub Actions, Docker, Trivy, GHCR) | ✅ terminé — [v0.1.1](https://github.com/franckfourrier/taskops-platform/releases) |
| 2 | Infrastructure AWS avec Terraform (OIDC, dev/prod, surveillance, dérive) | ✅ terminé |
| 3 | Déploiement Kubernetes (Kind, Helm, HPA, Argo CD / GitOps) | ✅ terminé |
| 4 | Monitoring Prometheus / Grafana / Alertmanager (métriques RED, alertes Telegram) | ✅ terminé — [v0.2.0](https://github.com/franckfourrier/taskops-platform/releases) |
| 5 | Architecture haute disponibilité (3 zones, CloudNativePG, NetworkPolicies, Sealed Secrets, cert-manager, Argo Rollouts) | 🔄 5 étapes sur 6 (reste : canary Argo Rollouts) |

## Vue d'ensemble

```mermaid
flowchart LR
    dev([Développeur]) -->|PR| gh[GitHub]
    gh --> ci[CI : lint, tests, build,<br/>Trivy, smoke test]
    ci -->|push main / tag| ghcr[(GHCR<br/>taskops-api)]
    gh --> tf[Terraform CI :<br/>fmt, validate, tflint, plan]
    tf -->|plan commenté| gh
    tf -->|merge + validation manuelle| apply[apply]
    apply -->|OIDC, sans clé| aws[(AWS eu-west-3)]
    ghcr -->|image| aws
    drift[Dérive : plan chaque nuit] -->|OIDC lecture seule| aws
```

## L'application

| Route | Rôle |
|-------|------|
| `GET /health` | Health check (`{"status": "ok"}`) utilisé par Docker, la CI, le smoke test et le monitoring |
| `GET /tasks` | Liste les tâches |
| `POST /tasks` | Crée une tâche (`{"title": "...", "done": false}`) |
| `GET /docs` | Documentation interactive (Swagger UI générée par FastAPI) |
| `GET /metrics` | Métriques Prometheus (interne au cluster, non publié par l'Ingress) |

Configuration : variable `DATABASE_URL` (PostgreSQL en compose/CI/K8s, SQLite dans `/srv/data` par défaut).
Sur Kubernetes, elle est construite à partir des identifiants générés par CloudNativePG (aucun secret manuel).

---

## Projet 1 — Pipeline CI/CD

### Stack et choix

| Outil | Rôle | Pourquoi |
|-------|------|----------|
| GitHub Actions | CI/CD | Intégré au dépôt, gratuit pour un dépôt public |
| pytest + PostgreSQL (service CI) | Tests | Tests contre une vraie base, comme en prod |
| Ruff | Lint + format (+ règles de sécurité `S`) | Très rapide, remplace flake8/isort/black |
| Docker multi-étapes, `python:3.12-slim` | Image | Légère (≈ 177 Mo, 55,7 Mo compressée), non-root, avec HEALTHCHECK |
| Smoke test | Démarrage réel | L'image doit répondre sur `/health` en moins de 30 s |
| Trivy | Scan de vulnérabilités | Bloque le pipeline sur une faille CRITICAL corrigeable |
| GHCR | Registre | Authentification par `GITHUB_TOKEN`, aucun secret à gérer |

### Pipeline

```
push / PR ─► lint (ruff) ─► tests (pytest + Postgres) ─► build ─► smoke test ─► scan Trivy ─► push GHCR
                                                                                    (main et tags v* uniquement)
```

Tags produits : SHA complet du commit, `latest` sur `main`, et `1.2.3` / `1.2` sur une release `v1.2.3`.

### Gouvernance et sécurité

- Branche `main` **protégée** (ruleset) : PR obligatoire, checks requis, force-push et suppression interdits.
- Image exécutée en **non-root** (UID 10001), mises à jour OS appliquées au build.
- Aucun secret dans le code : `GITHUB_TOKEN` éphémère pour GHCR.
- Permissions des workflows au **moindre privilège**, actions GitHub **épinglées par SHA** de commit.

### Lancer en local

```bash
make install && make lint && make test   # venv + lint + tests
make up                                  # API + PostgreSQL via docker compose
until curl -sf localhost:8000/health; do sleep 1; done
curl -X POST localhost:8000/tasks -H 'Content-Type: application/json' -d '{"title":"test"}'
make down
```

---

## Projet 2 — Infrastructure AWS avec Terraform

### Architecture (par environnement)

```mermaid
flowchart TB
    internet((Internet)) --> igw[Internet Gateway]
    subgraph vpc["VPC taskops-ENV (10.0.0.0/16 dev · 10.1.0.0/16 prod)"]
        igw --> rtp[Table de routage publique<br/>0.0.0.0/0 → IGW]
        subgraph pub["Sous-réseau public"]
            sg{{Security Group<br/>HTTP 80 · SSH optionnel /32}} --> ec2["EC2 Amazon Linux 2023<br/>t3.micro dev · t3.small prod<br/>IMDSv2 · disque chiffré<br/>Docker → taskops-api:0.1.1"]
        end
        subgraph priv["Sous-réseau privé (sans accès Internet)"]
            reserve[réservé : base de données]
        end
    end
    ec2 -. métriques .-> cw[CloudWatch<br/>CPU > 80 % · contrôle système]
    cw -->|alerte| sns[SNS → e-mail]
    cw -->|panne matérielle| recover[Récupération automatique]
```

### Organisation du code

```
terraform/
├── bootstrap/        # bucket S3 du state (chiffré, versionné, privé) — appliqué une seule fois
├── github-oidc/      # fédération GitHub → AWS : rôles taskops-gha-plan / taskops-gha-apply
├── modules/
│   ├── network/      # VPC, sous-réseaux public/privé, IGW, routage
│   ├── compute/      # EC2, Security Group, user_data qui lance l'API
│   └── monitoring/   # SNS + alarmes CloudWatch
├── envs/             # dev.tfvars, prod.tfvars, *.s3.tfbackend (un state par environnement)
└── main.tf, variables.tf, outputs.tf, providers.tf
```

### Workflow Terraform

| Événement | Ce qui se passe |
|-----------|-----------------|
| Pull request | `fmt`, `validate`, `tflint`, puis **plan `dev` et `prod` en parallèle**, publiés en commentaire de la PR |
| Merge sur `main` | `apply` sur **dev**, après **validation manuelle** (environnement GitHub protégé), puis smoke test de l'API |
| Lancement manuel | `plan`, `apply` ou `destroy` sur `dev` ou `prod` — **prod uniquement depuis `main`** |
| Chaque nuit (04:17, Douala) | **Détection de dérive** : `plan -detailed-exitcode` sur dev et prod ; échec si l'infra a été modifiée hors de Terraform |

### Sécurité

- **Aucune clé AWS** dans le dépôt ni dans GitHub : authentification **OIDC** avec des droits temporaires.
  - `taskops-gha-plan` : lecture seule, utilisable uniquement depuis une PR ou `main` de ce dépôt.
  - `taskops-gha-apply` : utilisable uniquement depuis les environnements GitHub protégés `dev` et `prod`.
  - Règles de confiance basées sur les **identifiants immuables** du compte et du dépôt (protection contre la recréation d'un dépôt homonyme).
- State Terraform dans S3 : chiffré, versionné, accès public bloqué, **verrouillage natif** (`use_lockfile`).
- IAM au **moindre privilège** (pas d'`AdministratorAccess`), MFA sur les comptes humains.
- Instance : **IMDSv2 obligatoire**, disque chiffré, SSH **désactivé par défaut**.

### Lancer en local

```bash
cd terraform
terraform init -backend-config=envs/dev.s3.tfbackend
terraform plan -var-file=envs/dev.tfvars -out=tfplan && terraform apply tfplan
terraform plan -destroy -var-file=envs/dev.tfvars -out=destroy.tfplan && terraform apply destroy.tfplan
```

Coût : quelques centimes par heure d'utilisation ; l'infrastructure est détruite après chaque test.

---

## Projet 3 — Kubernetes en GitOps

### Architecture

```mermaid
flowchart LR
    git[(GitHub<br/>main : charts/taskops)] -->|surveille| argo[Argo CD<br/>auto-sync · prune · self-heal]
    subgraph kind["Cluster Kind taskops (1 control-plane + 2 workers)"]
        argo -->|applique le chart| ns
        subgraph ns["namespace taskops"]
            ing[Ingress] --> svc[Service taskops-api]
            svc --> api["Deployment taskops-api<br/>2 à 6 pods (HPA 70 % CPU)<br/>PDB minAvailable 1"]
            api -->|init container : attente| pg[("StatefulSet postgres<br/>volume persistant 1 Gi")]
        end
        traefik[Traefik<br/>ports 80/443 de l'hôte] --> ing
        ms[metrics-server] -.-> api
    end
    user([Navigateur]) -->|http://hôte/docs| traefik
```

### Organisation

```
charts/taskops/            # chart Helm de l'application (source de vérité pour Argo CD)
├── values.yaml            # image, réplicas, ressources, PostgreSQL, Ingress, HPA, PDB
├── dashboards/            # tableau de bord Grafana (JSON)
└── templates/             # deployment, postgres, service, ingress, hpa, pdb, servicemonitor, prometheusrule, dashboard
kubernetes/
├── kind-config.yaml       # cluster local + réglages etcd/leader-election pour VM lente
├── platform/              # valeurs Helm : Traefik, metrics-server, Argo CD, kube-prometheus-stack,
│                          #   CloudNativePG, Sealed Secrets, cert-manager
├── secrets/               # SealedSecrets (chiffrés, versionnables)
└── argocd/taskops-app.yaml  # Application Argo CD (auto-sync, prune, self-heal)
```

### Points clés

| Sujet | Mise en œuvre |
|-------|---------------|
| Sécurité des pods | non-root (UID 10001), système de fichiers en lecture seule, aucune capability, seccomp `RuntimeDefault` |
| Santé | readiness et liveness probes sur `/health`, `pg_isready` pour PostgreSQL |
| Démarrage ordonné | init container qui attend PostgreSQL avant de lancer l'API |
| Persistance | StatefulSet + volume : données conservées à travers 3 migrations (manifestes → Helm → Argo CD) |
| Autoscaling | HPA 2 à 6 réplicas, validé sous charge (2 → 6 → 2) |
| Disponibilité | PodDisruptionBudget : au moins 1 pod pendant une maintenance |
| GitOps | Argo CD synchronise `main` ; une suppression manuelle est réparée automatiquement (self-heal) |
| Secrets | mot de passe PostgreSQL créé dans le cluster, jamais dans Git (Sealed Secrets prévu au projet 5) |
| CI | `helm lint --strict` + rendu validé par kubeconform à chaque PR |

### Lancer en local

```bash
kind create cluster --config kubernetes/kind-config.yaml
helm upgrade --install traefik traefik/traefik --version 42.4.1 -n traefik --create-namespace -f kubernetes/platform/traefik-values.yaml
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system -f kubernetes/platform/metrics-server-values.yaml
helm upgrade --install argocd argo/argo-cd --version 10.18.2 -n argocd --create-namespace -f kubernetes/platform/argocd-values.yaml
kubectl create namespace taskops
kubectl -n taskops create secret generic taskops-db --from-literal=POSTGRES_PASSWORD=... --from-literal=DATABASE_URL=...
kubectl apply -f kubernetes/argocd/taskops-app.yaml   # Argo CD déploie le chart depuis GitHub
```

## Projet 4 — Monitoring et alertes

### Architecture

```mermaid
flowchart LR
    subgraph taskops["namespace taskops"]
        api["API taskops-api<br/>/metrics (RED)"]
        sm[ServiceMonitor] -.->|cible| api
        rule[PrometheusRule<br/>4 alertes]
        dash[ConfigMap<br/>tableau de bord]
    end
    subgraph monitoring["namespace monitoring (kube-prometheus-stack)"]
        prom[(Prometheus<br/>rétention 7 j · 10 Gi)]
        am[Alertmanager]
        graf[Grafana]
        ksm[kube-state-metrics] --> prom
        ne[node-exporter x3] --> prom
    end
    prom -->|collecte toutes les 30 s| api
    rule --> prom
    prom -->|alertes| am -->|bot| tg([Telegram])
    dash -->|sidecar| graf -->|requêtes PromQL| prom
```

Le chart `charts/taskops` livre lui-même sa surveillance (ServiceMonitor, règles, tableau de bord) :
Argo CD la déploie avec l'application, sans action manuelle.

### Métriques de l'API (méthode RED)

| Métrique | Type | Usage |
|----------|------|-------|
| `taskops_http_requests_total{method, route, status}` | Counter | **R**ate (débit) et **E**rreurs (`status=~"5.."`) |
| `taskops_http_request_duration_seconds{method, route}` | Histogram | **D**urée : latence p50 / p95 / p99 |
| `taskops_tasks_created_total` | Counter | Métrique métier |

`route` est le *modèle* de route (`/tasks`), et les URL inconnues sont regroupées sous `inconnue` :
le nombre de séries reste borné (cardinalité maîtrisée). `/health` et `/metrics` ne sont pas comptés.

### Alertes

| Alerte | Condition | Gravité |
|--------|-----------|---------|
| `TaskOpsAPIDown` | aucune instance joignable pendant 2 min | critical |
| `TaskOpsHighErrorRate` | plus de 5 % de réponses 5xx pendant 5 min | critical |
| `TaskOpsHighLatency` | latence p95 > 500 ms pendant 10 min | warning |
| `TaskOpsPodRestarting` | plus de 2 redémarrages en 15 min | warning |

Notifications **Telegram** (🔥 alerte / ✅ résolu, en français), regroupées et rappelées toutes les 4 h.
Testé sur une vraie panne : alerte reçue 2 min 30 après l'arrêt de l'API, résolution 5 min après son retour.

### Points clés

| Sujet | Mise en œuvre |
|-------|---------------|
| Secrets | mot de passe Grafana et jeton du bot Telegram dans des Secrets créés à la main, jamais dans Git |
| Exposition | `/metrics` non publié (liste blanche de chemins dans l'Ingress) |
| Bruit | `Watchdog` (preuve de vie de la chaîne) et une alerte connue de Kind non notifiées, choix documenté |
| Version | `kube-prometheus-stack` 93.5.0 épinglée ; tableau de bord versionné dans le chart |

### Lancer en local

```bash
helm upgrade --install kps prometheus-community/kube-prometheus-stack --version 93.5.0 \
  -n monitoring --create-namespace -f kubernetes/platform/kube-prometheus-stack-values.yaml
kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password=...
kubectl -n monitoring create secret generic alertmanager-telegram --from-literal=bot-token=...
kubectl -n monitoring port-forward svc/kps-grafana 3000:80   # tableau « TaskOps / API (RED) »
```

## Projet 5 — Haute disponibilité

### Architecture

```mermaid
flowchart TB
    user([Client]) -->|HTTPS cert-manager / HTTP| traefik[Traefik]
    subgraph a["zone-a (taskops-worker)"]
        api1[API]
        pg1[("PostgreSQL")]
    end
    subgraph b["zone-b (taskops-worker2)"]
        api2[API]
        pg2[("PostgreSQL")]
    end
    subgraph c["zone-c (taskops-worker3)"]
        api3[API]
        pg3[("PostgreSQL")]
    end
    traefik --> api1 & api2 & api3
    api1 & api2 & api3 -->|Service taskops-pg-rw : toujours le primaire| pg2
    pg2 -. réplication continue .-> pg1 & pg3
    op[Opérateur CloudNativePG] -. bascule automatique .-> pg1 & pg2 & pg3
```

Le rôle de primaire change de zone lors d'une bascule ; l'API suit automatiquement via le Service `-rw`.

### Mise en œuvre

| Sujet | Mise en œuvre |
|-------|---------------|
| Zones | 3 workers Kind étiquetés `topology.kubernetes.io/zone` (label standard des clouds) |
| API | `topologySpreadConstraints` par zone (strict) et par nœud ; HPA 3 à 6 ; PDB `minAvailable: 2` ; `nodeTaintsPolicy: Honor` |
| PostgreSQL | **CloudNativePG** : 1 primaire + 2 réplicas, anti-affinité **obligatoire** par zone, bascule automatique, métriques Prometheus |
| Réseau | **NetworkPolicies** : tout refusé par défaut, liste blanche (Traefik/Prometheus/kubelet → API, API → PostgreSQL, réplication, opérateur, DNS) |
| Secrets | **Sealed Secrets** : secrets chiffrés dans Git (`kubernetes/secrets/`) ; une seule clé privée à sauvegarder hors de Git |
| TLS | **cert-manager** : CA interne, certificat 90 jours renouvelé 30 jours avant l'expiration, nouvelle clé à chaque fois |
| Reprise après sinistre | `make cluster` (`scripts/bootstrap-cluster.sh`) recrée tout depuis Git, avec versions épinglées et verrou anti double exécution |

### Tests de résilience (mesurés)

| Scénario | Résultat |
|----------|----------|
| Cluster supprimé puis reconstruit depuis Git | ≈ 20 min, application `Synced/Healthy` |
| Perte brutale d'une zone (nœud arrêté) pendant le trafic | **95,3 %** de requêtes réussies ; 47 s d'erreurs partielles le temps que le nœud soit déclaré mort |
| Crash du primaire PostgreSQL pendant des écritures | bascule automatique en **21 s**, aucune donnée perdue, aucune intervention |
| Pod « intrus » (autre namespace, puis `taskops`) → PostgreSQL | **bloqué** (`Connection timed out`) ; Prometheus collecte toujours les 6 cibles |
| HTTPS avec vérification du certificat | 200 ; HTTP inchangé |

---

## Ce qui a cassé et comment je l'ai réparé

Quinze pannes réelles, documentées dans [docs/troubleshooting.md](docs/troubleshooting.md) :

1. `Connection reset` juste après `make up` — « démarré » n'est pas « prêt ».
2. Image au-dessus de 200 Mo — `pip` et `.pyc` embarqués dans le venv.
3. Conteneur seul en échec — SQLite non inscriptible par l'utilisateur non-root.
4. Clé d'accès AWS exposée — rotation immédiate sans afficher le nouveau secret.
5. GitHub Actions refusé par AWS — nouveau format du sujet OIDC (identifiants immuables).
6. Scheduler et controller-manager en boucle — etcd lent sur VM, baux de leader perdus.
7. Init container bloqué — `pg_isready` sans utilisateur explicite en non-root (« no attempt »).
8. Argo CD bloqué en « Progressing » — Ingress sans adresse ; rolling update impossible avec `hostPort`.
9. `helm --wait` dépassé à l'installation du monitoring — téléchargements d'images lents, release « failed » mais pods sains.
10. Alerte `KubeAPIErrorBudgetBurn` permanente sur Kind — etcd lent ; non notifiée en DEV, choix documenté.
11. Notification Telegram sans namespace — `sum()` supprime les labels de l'alerte.
12. `/metrics` public — Ingress trop large, remplacé par une liste blanche de chemins.
13. Docker bloqué — deux reconstructions simultanées ; verrou `flock` dans le script.
14. Grafana tué au premier démarrage — sonde de vie trop stricte pour un disque lent.
15. PostgreSQL sans instance — etcd lent, opérateur sans bail, interblocage bascule / copie ; réparé sans perte de données.

## Améliorations prévues

- Migrations de schéma avec Alembic (au lieu de `create_all`).
- Signature des images (cosign) et SBOM.
- Route `/` redirigeant vers `/docs`.
