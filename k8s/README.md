# Kubernetes — Déploiement de l'application

Ce dossier contient les manifests Kubernetes organisés avec Kustomize.
L'objectif est de déployer l'application sur deux clusters :
- **k3s** (EC2) — application seule, pour valider le déploiement de base
- **EKS** (AWS managé) — application + stack ELK complète

---

## 1. Prérequis

- `kubectl` installé (`kubectl version --client`)
- Images Docker pushées sur ECR (voir `apps/README.md`)
- Terraform apply terminé avec succès

### Vérifier kubectl
```bash
kubectl version --client
```

### Rendre KUBECONFIG permanent
```bash
# Pour k3s — à ajouter dans ~/.bashrc pour ne pas le retaper à chaque session
echo 'export KUBECONFIG=~/DevOpsFormation/TP_Mois3/ansible/kubeconfig-k3s.yaml' >> ~/.bashrc
source ~/.bashrc
```

---

## 2. Comprendre la structure Kustomize

```
k8s/
├── base/           Manifests communs aux deux clusters
│                    (Deployments, Services, HPA, PDB, ConfigMap)
├── monitoring/     Stack ELK (EKS uniquement — trop lourde pour k3s t3.micro)
└── overlays/
    ├── eks/        base + monitoring + Ingress ALB
    └── k3s/        base uniquement + Ingress nginx
```

Pour voir le YAML final sans rien appliquer :
```bash
kubectl kustomize k8s/overlays/k3s/    # aperçu k3s
kubectl kustomize k8s/overlays/eks/    # aperçu EKS
```

---

## 3. Préparer les secrets

⚠️ Ne modifie JAMAIS `base/secret.yaml` avec de vraies valeurs.
Ce fichier garde les placeholders comme documentation de structure.
Les vraies valeurs sont injectées directement dans le cluster via kubectl.

### Récupérer les credentials RDS

```bash
# Récupère le secret depuis AWS Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id capstone-staging-rds-credentials-v3 \
  --region eu-west-1 \
  --query SecretString \
  --output text)

# Exporte chaque valeur
export DB_HOST=$(terraform -chdir=terraform/environments/staging \
  output -raw rds_endpoint | cut -d: -f1)
export DB_PORT="5432"
export DB_NAME=$(echo $SECRET | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['dbname'])")
export DB_USER=$(echo $SECRET | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['username'])")
export DB_PASSWORD=$(echo $SECRET | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['password'])")

# Vérifie que les variables sont bien remplies (pas vides, pas "placeholder")
echo "DB_HOST=$DB_HOST"
echo "DB_USER=$DB_USER"
echo "DB_NAME=$DB_NAME"
```

### Créer les secrets dans le cluster

Ces commandes sont idempotentes — elles créent ou mettent à jour :

```bash
kubectl create namespace capstone --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic db-credentials \
  --namespace capstone \
  --from-literal=DB_HOST=$DB_HOST \
  --from-literal=DB_PORT=$DB_PORT \
  --from-literal=DB_NAME=$DB_NAME \
  --from-literal=DB_USER=$DB_USER \
  --from-literal=DB_PASSWORD=$DB_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

# Pour ELK (EKS uniquement)
kubectl create secret generic elk-credentials \
  --namespace capstone \
  --from-literal=ELASTIC_PASSWORD="ChoisisUnMotDePasseFort123!" \
  --dry-run=client -o yaml | kubectl apply -f -


```

Vérifie :
```bash
kubectl get secrets -n capstone
# NAME             TYPE     DATA
# db-credentials   Opaque   5
# elk-credentials  Opaque   1   (EKS uniquement)
```

---

## 4. Déploiement sur k3s

### 4.1 Configurer kubectl pour k3s

```bash
export KUBECONFIG=~/DevOpsFormation/TP_Mois3/ansible/kubeconfig-k3s.yaml
kubectl get nodes
# ip-10-0-0-10   Ready   control-plane   Xm
```

### 4.2 Configurer le pull ECR sur k3s

Le token ECR expire toutes les 12h — à relancer si tu as des `ImagePullBackOff`.

```bash
export ECR_REGISTRY=$(terraform -chdir=terraform/environments/staging \
  output -raw ecr_registry_url)
export ECR_TOKEN=$(aws ecr get-login-password --region eu-west-1)
export K3S_IP=$(terraform -chdir=terraform/environments/staging \
  output -raw k3s_public_ip)

# Envoie la config sur la VM (EOF sans guillemets = interpolation active)
ssh -i ~/.ssh/capstone_k3s ubuntu@$K3S_IP \
  "sudo mkdir -p /etc/rancher/k3s && sudo tee /etc/rancher/k3s/registries.yaml > /dev/null << EOF
mirrors:
  $ECR_REGISTRY:
    endpoint:
      - \"https://$ECR_REGISTRY\"
configs:
  \"$ECR_REGISTRY\":
    auth:
      username: AWS
      password: $ECR_TOKEN
EOF
sudo systemctl restart k3s"

# Vérifie que le fichier contient les vraies valeurs (pas des noms de variables)
ssh -i ~/.ssh/capstone_k3s ubuntu@$K3S_IP \
  "sudo cat /etc/rancher/k3s/registries.yaml"

sleep 10
kubectl get nodes
```

### 4.4 Appliquer les manifests

```bash
kubectl apply -k k8s/overlays/k3s/
```

### 4.5 Vérifier le déploiement

```bash
kubectl get pods -n capstone -w
```

État attendu sur k3s (ELK absent volontairement) :
```
NAME                      READY   STATUS    RESTARTS
api-users-xxx             1/1     Running   0
api-orders-xxx            1/1     Running   0
api-products-xxx          1/1     Running   0
frontend-xxx              1/1     Running   0
```

Si un pod reste en `0/1 Running` (conteneur lancé mais readiness probe KO) :
```bash
kubectl logs deploy/api-users -n capstone --tail=30
# L'erreur dans les logs indique ce qui bloque (DB, variable manquante, etc.)
```

Si un pod est en `ImagePullBackOff` :
```bash
kubectl describe pod <nom> -n capstone
# Section Events: indique si c'est un problème d'auth ECR ou d'image inexistante
# Si auth ECR → relancer la section 4.2 (token expiré)
```

### 4.6 Tester l'accès

```bash
K3S_IP=$(terraform -chdir=terraform/environments/staging output -raw k3s_public_ip)

curl -I http://$K3S_IP/
curl http://$K3S_IP/api/users/health
curl http://$K3S_IP/api/orders/health
curl http://$K3S_IP/api/products/health
```

---

## 5. Déploiement sur EKS

### 5.1 Configurer kubectl pour EKS

```bash
aws eks update-kubeconfig \
  --region eu-west-1 \
  --name capstone-staging-eks

kubectl get nodes
# 2 nœuds m7i-flex.large en Ready
```

### 5.2 Créer les secrets sur EKS

Les variables exportées à l'étape 3 doivent toujours être actives.
Si tu as ouvert un nouveau terminal, réexporte-les.

```bash
kubectl create namespace capstone --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic db-credentials \
  --namespace capstone \
  --from-literal=DB_HOST=$DB_HOST \
  --from-literal=DB_PORT=$DB_PORT \
  --from-literal=DB_NAME=$DB_NAME \
  --from-literal=DB_USER=$DB_USER \
  --from-literal=DB_PASSWORD=$DB_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl exec -n capstone elasticsearch-0 -- \
  curl -s -u elastic:ChoisisUnMotDePasseFort123! \
  -X POST "localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d '{"password":"ChoisisUnMotDePasseFort123!"}'


# 1. Appliquer ES
kubectl apply -f elasticsearch.yaml
```

### 5.3 Installer le AWS Load Balancer Controller

Requis pour que l'Ingress ALB fonctionne sur EKS.

```bash
# cert-manager (dépendance)
kubectl apply --validate=false -f \
  https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=120s

# AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=capstone-staging-eks \
  --set serviceAccount.create=true \
  --set region=eu-west-1 \
  --set vpcId=$(terraform -chdir=terraform/environments/staging output -raw vpc_id)

kubectl get pods -n kube-system | grep aws-load-balancer
# aws-load-balancer-controller-xxx   1/1   Running
```

### 5.4 Appliquer les manifests EKS (app + ELK)

```bash
kubectl apply -k k8s/overlays/eks/
```

### 5.5 Vérifier

```bash
kubectl get pods -n capstone -w
```

État attendu sur EKS (avec ELK) :
```
NAME                      READY   STATUS    RESTARTS
api-users-xxx             1/1     Running   0
api-orders-xxx            1/1     Running   0
api-products-xxx          1/1     Running   0
frontend-xxx              1/1     Running   0
elasticsearch-0           1/1     Running   0
logstash-xxx              1/1     Running   0
kibana-xxx                1/1     Running   0
filebeat-xxx              1/1     Running   0
elastalert-xxx            1/1     Running   0
```

Elasticsearch prend 2-3 minutes à démarrer — c'est normal.

```bash
# L'ALB met 2-3 minutes à être provisionné par AWS
kubectl get ingress -n capstone -w

ALB_URL=$(kubectl get ingress capstone-ingress -n capstone \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -I http://$ALB_URL/
curl http://$ALB_URL/api/users/health
```

---

## 6. Diagnostics

```bash
# Événements du namespace (erreurs récentes)
kubectl get events -n capstone --sort-by='.lastTimestamp'

# Logs d'un service
kubectl logs -l app=api-users -n capstone --tail=50 -f

# Détail d'un pod en erreur
kubectl describe pod <nom> -n capstone

# Autoscaling
kubectl get hpa -n capstone

# Consommation ressources
kubectl top pods -n capstone
```

---

## 7. Rollback

```bash
kubectl rollout history deployment/api-users -n capstone
kubectl rollout undo deployment/api-users -n capstone
kubectl rollout status deployment/api-users -n capstone
```

---

## 8. Nettoyer

```bash
kubectl delete -k k8s/overlays/k3s/   # sur k3s
kubectl delete -k k8s/overlays/eks/   # sur EKS
```