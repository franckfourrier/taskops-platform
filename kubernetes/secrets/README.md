# Secrets chiffrés (Sealed Secrets)

Ces fichiers sont des `SealedSecret` : ils sont **chiffrés** avec la clé publique du
contrôleur Sealed Secrets du cluster et peuvent être versionnés sans risque.
Seul le contrôleur (clé privée, namespace `kube-system`) peut les déchiffrer.

| Fichier | Secret produit | Usage |
|---------|----------------|-------|
| `monitoring-grafana-admin.yaml` | `monitoring/grafana-admin` | compte admin de Grafana |
| `monitoring-alertmanager-telegram.yaml` | `monitoring/alertmanager-telegram` | jeton du bot Telegram |

Créer ou modifier un secret :

```bash
kubectl create secret generic NOM -n NAMESPACE --from-literal=cle=valeur --dry-run=client -o yaml \
  | kubeseal --format yaml > kubernetes/secrets/NAMESPACE-NOM.yaml
```

**Reprise après sinistre :** seule la clé privée du contrôleur doit être sauvegardée hors de Git
(`~/sauvegarde-secrets/sealed-secrets-cles.yaml`) ; le script `scripts/bootstrap-cluster.sh`
la restaure avant d'installer le contrôleur.
