#!/usr/bin/env bash
# Reconstruit le cluster TaskOps de zéro, uniquement depuis Git (reprise après sinistre).
# Usage : scripts/bootstrap-cluster.sh [dossier_des_secrets]
# Les secrets applicatifs sont dans Git, chiffrés (kubernetes/secrets/, Sealed Secrets).
# Seule la clé privée du contrôleur, jamais dans Git, est restaurée depuis le dossier
# indiqué (par défaut ~/sauvegarde-secrets).
set -euo pipefail
cd "$(dirname "$0")/.."

# Une seule reconstruction à la fois : deux exécutions simultanées
# se disputent les conteneurs et bloquent Docker (panne n° 13)
exec 9>/tmp/taskops-bootstrap.lock
flock -n 9 || { echo "Une reconstruction est déjà en cours." >&2; exit 1; }

SECRETS_DIR="${1:-$HOME/sauvegarde-secrets}"
DEBUT=$(date +%s)
etape() { printf '\n==> [%4ss] %s\n' "$(( $(date +%s) - DEBUT ))" "$*"; }

[ -d "$SECRETS_DIR" ] || { echo "Dossier de secrets introuvable : $SECRETS_DIR" >&2; exit 1; }

etape "Cluster Kind (1 control-plane + 3 workers / 3 zones)"
if ! kind get clusters | grep -qx taskops; then
  kind create cluster --config kubernetes/kind-config.yaml --wait 5m
fi
kubectl get nodes -L topology.kubernetes.io/zone

etape "Dépôts Helm"
helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update >/dev/null
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets --force-update >/dev/null
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo update >/dev/null

etape "Traefik (Ingress)"
helm upgrade --install traefik traefik/traefik --version 42.4.1 \
  -n traefik --create-namespace -f kubernetes/platform/traefik-values.yaml --wait --timeout 15m

etape "metrics-server (HPA)"
helm upgrade --install metrics-server metrics-server/metrics-server --version 3.14.0 \
  -n kube-system -f kubernetes/platform/metrics-server-values.yaml --wait --timeout 15m

etape "Clé privée Sealed Secrets restaurée depuis $SECRETS_DIR"
for ns in taskops monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
for f in "$SECRETS_DIR"/*.yaml; do
  # on retire les champs propres à l'ancien cluster
  sed -e '/^ *resourceVersion:/d' -e '/^ *uid:/d' -e '/^ *creationTimestamp:/d' "$f" | kubectl apply -f -
done

etape "Sealed Secrets (déchiffre les secrets versionnés dans kubernetes/secrets/)"
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets --version 2.22.0 \
  -n kube-system -f kubernetes/platform/sealed-secrets-values.yaml --wait --timeout 15m
kubectl apply -f kubernetes/secrets/
for s in grafana-admin alertmanager-telegram; do
  kubectl -n monitoring wait --for=create secret/$s --timeout=2m
done

etape "kube-prometheus-stack (fournit les CRD ServiceMonitor / PrometheusRule du chart)"
helm upgrade --install kps prometheus-community/kube-prometheus-stack --version 93.5.0 \
  -n monitoring -f kubernetes/platform/kube-prometheus-stack-values.yaml --wait --timeout 20m

etape "cert-manager (certificats TLS)"
helm upgrade --install cert-manager jetstack/cert-manager --version v1.21.3 \
  -n cert-manager --create-namespace -f kubernetes/platform/cert-manager-values.yaml --wait --timeout 15m
kubectl apply -f kubernetes/platform/pki.yaml
kubectl wait --for=condition=Ready clusterissuer/plateforme-ca --timeout=2m

etape "Opérateur CloudNativePG (PostgreSQL haute disponibilité)"
helm upgrade --install cnpg cnpg/cloudnative-pg --version 0.29.2 \
  -n cnpg-system --create-namespace -f kubernetes/platform/cnpg-values.yaml --wait --timeout 15m

etape "Argo CD"
helm upgrade --install argocd argo/argo-cd --version 10.18.2 \
  -n argocd --create-namespace -f kubernetes/platform/argocd-values.yaml --wait --timeout 15m

etape "Application TaskOps (GitOps : Argo CD déploie le chart depuis GitHub)"
kubectl apply -f kubernetes/argocd/taskops-app.yaml
ETAT=""
for _ in $(seq 1 90); do
  ETAT=$(kubectl -n argocd get application taskops \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
  [ "$ETAT" = "Synced/Healthy" ] && break
  sleep 10
done
echo "Argo CD : ${ETAT:-inconnu}"

etape "Vérification de l'API"
curl -fsS http://localhost/health && echo
kubectl -n taskops get pods -o wide

etape "Reconstruction terminée"
