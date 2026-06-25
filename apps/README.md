# Applications — Build et push des images Docker vers ECR

Ce dossier contient le code source et les Dockerfiles de chaque service.
L'objectif de cette étape est de construire les images Docker localement
et de les pousser vers AWS ECR (Elastic Container Registry), le registre
privé d'images Docker d'AWS — l'équivalent de Docker Hub mais dans ton
compte AWS.

Une fois les images dans ECR, Kubernetes (EKS ou k3s) pourra les télécharger
pour démarrer les pods.

---

## 1. Prérequis

- Docker installé sur ta machine
- AWS CLI configurée (`aws sts get-caller-identity` doit répondre)
- Terraform apply effectué avec succès (les repos ECR doivent exister)

### Installer Docker

#### Linux (WSL/Ubuntu)
```bash
sudo apt update
sudo apt install docker.io
sudo usermod -aG docker $USER
newgrp docker          # recharge les groupes sans déconnecter
```

#### Vérifier
```bash
docker --version
docker run hello-world  # doit afficher "Hello from Docker!"
```

---

## 2. Récupérer l'URL du registry ECR

```bash
cd terraform/environments/staging
terraform output ecr_registry_url
```

Tu dois voir quelque chose comme :
```
"172030247215.dkr.ecr.eu-west-1.amazonaws.com"
```

Note cette valeur — on l'appellera `ECR_REGISTRY` dans toute la suite.
Exporte-la pour ne pas la retaper à chaque commande :

```bash
export ECR_REGISTRY=$(terraform output -raw ecr_registry_url)
echo $ECR_REGISTRY     # vérifie que c'est bien l'URL et pas une erreur
```

---

## 3. Authentifier Docker auprès d'ECR

ECR est un registry privé — Docker doit s'authentifier avant de pouvoir
pusher ou puller des images. AWS fournit un token temporaire (valable 12h)
via la CLI :

```bash
aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

Tu dois voir :
```
Login Succeeded
```

⚠️ Ce token expire au bout de 12h. Si tu as une erreur d'authentification
plus tard, relance cette commande.

---

## 4. Structure des apps

```
apps/
├── api-users/
│   ├── Dockerfile
│   └── src/
│       ├── index.js        (ou main.py selon ton choix)
│       └── ...
├── api-orders/
│   ├── Dockerfile
│   └── src/
├── api-products/
│   ├── Dockerfile
│   └── src/
└── frontend/
    ├── Dockerfile
    └── src/
```

## 5. Builder et pusher les images

On va faire l'opération pour chaque service. Le tag utilisé est `latest`
pour l'instant — dans le pipeline CI/CD ce sera remplacé par le hash du
commit Git.

### api-users
```bash
cd apps/api-users

docker build -t $ECR_REGISTRY/capstone-staging/api-users:1.1.1 .

docker push $ECR_REGISTRY/capstone-staging/api-users:1.1.1
```

### api-orders
```bash
cd ../api-orders

docker build -t $ECR_REGISTRY/capstone-staging/api-orders:1.1.1 .

docker push $ECR_REGISTRY/capstone-staging/api-orders:1.1.1
```

### api-products
```bash
cd ../api-products

docker build -t $ECR_REGISTRY/capstone-staging/api-products:1.1.1 .

docker push $ECR_REGISTRY/capstone-staging/api-products:1.1.1
```

### frontend
```bash
cd ../frontend

docker build -t $ECR_REGISTRY/capstone-staging/frontend:1.1.1 .

docker push $ECR_REGISTRY/capstone-staging/frontend:1.1.1
```

---

## 6. Vérifier que les images sont bien dans ECR

```bash
# Lister les images de api-users
aws ecr list-images \
  --repository-name capstone-staging/api-users \
  --region eu-west-1
```

Tu dois voir quelque chose comme :
```json
{
  "imageIds": [
    {
      "imageDigest": "sha256:abc123...",
      "imageTag": "latest"
    }
  ]
}
```

Tu peux aussi vérifier dans la console AWS :
Services → ECR → Repositories → capstone-staging/api-users → Images

---

## 7. Mettre à jour les manifests Kubernetes avec les vraies URLs

Tes manifests K8s ont des placeholders :
```yaml
image: "<ECR_REGISTRY>/capstone/api-users:<IMAGE_TAG>"
```

Pour tester manuellement (avant le pipeline CI/CD), remplace-les :

```bash
# Depuis la racine du projet
export IMAGE_TAG=latest

# Vérification : affiche le YAML final avec les vraies valeurs
sed "s|<ECR_REGISTRY>|$ECR_REGISTRY|g; s|<IMAGE_TAG>|$IMAGE_TAG|g" \
  k8s/overlays/k3s/kustomization.yaml
```

Dans le pipeline CI/CD (étape suivante), cette substitution sera
automatique via `envsubst` à chaque commit.

---

## 8. Problèmes courants

| Erreur | Cause | Solution |
|---|---|---|
| `no basic auth credentials` | Token ECR expiré | Relancer `aws ecr get-login-password ...` |
| `denied: Your authorization token has expired` | Idem | Idem |
| `repository does not exist` | Repo ECR pas encore créé | `terraform apply` dans `environments/staging` |
| `Cannot connect to the Docker daemon` | Docker pas démarré | `sudo service docker start` |
| `permission denied` | User pas dans le groupe docker | `sudo usermod -aG docker $USER && newgrp docker` |

---

## 10. Ce qui vient ensuite

Une fois les images dans ECR, on peut déployer sur Kubernetes :

```bash
# Sur k3s (test)
export KUBECONFIG=ansible/kubeconfig-k3s.yaml
kubectl apply -k k8s/overlays/k3s/

# Sur EKS (staging)
aws eks update-kubeconfig --region eu-west-1 --name capstone-staging-eks
kubectl apply -k k8s/overlays/eks/
```

Le pipeline CI/CD (étape Capstone) automatisera tout ça :
build → push ECR → substitution des variables → kubectl apply.
