#!/usr/bin/env bash
# Reconstruit le cluster TaskOps de zéro, uniquement depuis Git (reprise après sinistre).
# Usage : scripts/bootstrap-cluster.sh [dossier_des_secrets]
# Les secrets (jamais dans Git) sont restaurés depuis le dossier indiqué,
# par défaut ~/sauvegarde-secrets.
set -euo pipefail
cd "$(dirname "$0")/.."

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
helm repo update >/dev/null

etape "Traefik (Ingress)"
helm upgrade --install traefik traefik/traefik --version 42.4.1 \
  -n traefik --create-namespace -f kubernetes/platform/traefik-values.yaml --wait --timeout 15m

etape "metrics-server (HPA)"
helm upgrade --install metrics-server metrics-server/metrics-server --version 3.14.0 \
  -n kube-system -f kubernetes/platform/metrics-server-values.yaml --wait --timeout 15m

etape "Secrets restaurés depuis $SECRETS_DIR"
for ns in taskops monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
for f in "$SECRETS_DIR"/*.yaml; do
  # on retire les champs propres à l'ancien cluster
  sed -e '/^  resourceVersion:/d' -e '/^  uid:/d' -e '/^  creationTimestamp:/d' "$f" | kubectl apply -f -
done

etape "kube-prometheus-stack (fournit les CRD ServiceMonitor / PrometheusRule du chart)"
helm upgrade --install kps prometheus-community/kube-prometheus-stack --version 93.5.0 \
  -n monitoring -f kubernetes/platform/kube-prometheus-stack-values.yaml --wait --timeout 20m

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
