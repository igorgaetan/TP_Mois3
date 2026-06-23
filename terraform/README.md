# Terraform — Infrastructure AWS

## 1. Prérequis : créer un compte / utilisateur AWS

Si ce n'est pas déjà fait :

1. Va sur https://console.aws.amazon.com/iam/
2. Menu de gauche → "Users" → "Create user"
3. Donne un nom (ex: `terraform-deploy`)
4. Ne coche PAS "Provide user access to AWS Management Console"
5. Attache la policy `AdministratorAccess` (pour ce TP — en prod on restreindrait)
6. Une fois l'utilisateur créé, onglet "Security credentials" → "Create access key"
7. Choisis "Command Line Interface (CLI)" → confirme
8. Note immédiatement la paire générée :
   - Access Key ID (ex: `AKIA...`)
   - Secret Access Key (ex: `wJalrX...`)

⚠️ Le Secret Access Key ne sera affiché qu'une seule fois. S'il est perdu,
il faudra en régénérer un depuis la console IAM.

---

## 2. Installer la AWS CLI

### macOS
```bash
brew install awscli
```

### Linux (Debian/Ubuntu)
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Windows
Télécharge et lance l'installeur :
https://awscli.amazonaws.com/AWSCLIV2.msi

### Vérifier l'installation
```bash
aws --version
```

---

## 3. Configurer la AWS CLI avec tes clés

```bash
aws configure
```

Il va te demander 4 choses :
```
AWS Access Key ID [None]:     AKIA...        (depuis l'étape 1)
AWS Secret Access Key [None]: wJalrX...      (depuis l'étape 1)
Default region name [None]:   eu-west-1
Default output format [None]: json
```

Vérifie que ça fonctionne :
```bash
aws sts get-caller-identity
```

Tu dois voir ton `UserId`, `Account`, et `Arn`. Si tu as une erreur,
tes clés sont mal saisies — relance `aws configure` pour les corriger.

⚠️ Ne commit JAMAIS ces clés dans Git. Elles sont stockées localement dans
`~/.aws/credentials`, hors de ce dépôt.

---

## 4. Installer Terraform

### macOS
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### Linux (Debian/Ubuntu)
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install terraform
```

### Vérifier l'installation
```bash
terraform -version
# doit afficher >= 1.7.0
```

---

## 5. Structure du dossier

```
terraform/
├── bootstrap/
│   ├── main.tf         Crée le bucket S3 + table DynamoDB pour le state distant.
│   └── outputs.tf      À exécuter UNE SEULE FOIS. Son propre state reste en local
│                        (il ne peut pas se stocker lui-même dans le bucket qu'il crée).
│
├── modules/            Modules réutilisables — jamais exécutés directement.
│   ├── vpc/             Réseau : VPC, 5 subnets, IGW, NAT Gateway, routes.
│   ├── eks/             Cluster EKS managé + node group + IAM roles.
│   ├── rds/             Instance PostgreSQL + subnet group + secret manager.
│   └── ec2-k3s/         Instance EC2 Ubuntu pour héberger k3s (configurée par Ansible).
│
└── environments/
    └── staging/         Point d'entrée réel. Instancie tous les modules avec
        ├── backend.tf    les vraies valeurs. C'est CE dossier qu'on exécute.
        ├── providers.tf
        ├── main.tf
        ├── variables.tf
        ├── terraform.tfvars
        └── outputs.tf
```

Pourquoi séparer `modules/` et `environments/` ? Les modules ne contiennent
aucune valeur en dur — ils sont génériques et réutilisables. `environments/staging/`
leur donne les vraies valeurs. Un futur dossier `environments/prod/` pourra
réutiliser exactement les mêmes modules sans dupliquer de code.

---

## 6. Étape A — Bootstrap (créer le backend S3)

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="bucket_name=capstone-tfstate-igor-2026"
```

Remplace `igor-2026` par quelque chose d'unique à toi (les noms de bucket S3
sont globaux sur toute la planète AWS — pas uniquement sur ton compte).

Terraform te demande confirmation : tape `yes`.

Note les deux valeurs en sortie, tu en as besoin à l'étape suivante :
```
bucket_name    = "capstone-tfstate-igor-2026"
dynamodb_table = "capstone-tfstate-igor-2026-locks"
```

---

## 7. Étape B — Déployer toute l'infrastructure

```bash
cd terraform/environments/staging
```

Ouvre `backend.tf` et remplace les placeholders par les valeurs du bootstrap :
```hcl
backend "s3" {
  bucket         = "capstone-tfstate-igor-2026"       # ← ta valeur
  key            = "staging/vpc.tfstate"
  region         = "eu-west-1"
  dynamodb_table = "capstone-tfstate-igor-2026-locks" # ← ta valeur
  encrypt        = true
}
```

Copie et remplis le fichier de variables :
```bash
cp terraform.tfvars.example terraform.tfvars
```

Contenu attendu dans `terraform.tfvars` :
```hcl
region = "eu-west-1"
name   = "capstone-staging"
azs    = ["eu-west-1a", "eu-west-1b"]

# Génère une clé si tu n'en as pas :
# ssh-keygen -t ed25519 -f ~/.ssh/capstone_k3s
# puis : cat ~/.ssh/capstone_k3s.pub
ssh_public_key = "ssh-ed25519 AAAA... user@machine"

# Trouve ton IP publique : curl ifconfig.me
# Ajoute /32 à la fin — c'est le masque qui signifie "cette IP exacte uniquement"
allowed_ssh_cidr = "TON_IP/32"
```

Lance le déploiement :
```bash
terraform init
terraform plan    # affiche ce qui VA être créé, sans rien toucher
terraform apply   # crée les ressources, tape "yes" pour confirmer
```

⚠️ La création prend 20-30 minutes au total :
- EKS control plane : ~15 minutes (AWS provisionne le cluster en arrière-plan)
- EKS node group : ~10 minutes supplémentaires
- RDS : ~5 minutes
- Le reste (VPC, EC2, IAM) : quasi-instantané

Ne tue pas la commande si elle semble bloquée — c'est normal.

---

## 8. Ce que ça crée concrètement

Une fois `apply` terminé avec succès, tu as sur AWS :

### Réseau
| Ressource | Valeur | Rôle |
|---|---|---|
| VPC | 10.0.0.0/16 | Réseau isolé global |
| Subnet public | 10.0.0.0/24 — AZ1 | EC2 k3s, NAT Gateway |
| Subnet privé compute 0 | 10.0.1.0/24 — AZ1 | Nœuds EKS |
| Subnet privé compute 1 | 10.0.4.0/24 — AZ2 | Nœuds EKS (2e AZ exigée par EKS) |
| Subnet privé data 0 | 10.0.2.0/24 — AZ1 | RDS primaire |
| Subnet privé data 1 | 10.0.3.0/24 — AZ2 | RDS secondaire |
| Internet Gateway | — | Entrée/sortie Internet pour le subnet public |
| NAT Gateway | dans subnet public | Sortie Internet pour les subnets privés compute |

Les subnets data n'ont aucune route Internet (ni entrante ni sortante) —
la base de données est totalement isolée du monde extérieur.

### Compute
| Ressource | Détail |
|---|---|
| Cluster EKS | `capstone-staging-eks`, Kubernetes 1.31 |
| Node group EKS | 2 nœuds `t3.micro` (Free Tier), autoscaling 1-4 |
| EC2 k3s | `t3.micro` Ubuntu 22.04, IP publique, configuré par Ansible |

### Données
| Ressource | Détail |
|---|---|
| RDS PostgreSQL 16 | `db.t3.micro`, chiffré, dans les subnets data isolés |
| Secret Manager | Credentials RDS jamais en clair dans le code |

### Outputs importants après apply
```
eks_cluster_name     = "capstone-staging-eks"
eks_cluster_endpoint = "https://..."
k3s_public_ip        = "X.X.X.X"     ← IP de la VM, utilisée par Ansible
rds_endpoint         = "capstone-staging-postgres.xxx.eu-west-1.rds.amazonaws.com:5432"
rds_secret_arn       = "arn:aws:secretsmanager:eu-west-1:..."  ← utilisé par le pipeline
```

Pour revoir ces valeurs à tout moment :
```bash
terraform output
```

---

## 9. Note Free Tier

Les instances sont en `t3.micro` pour rester dans le Free Tier AWS.
En production réelle, utiliser au minimum :
- `t3.medium` pour les nœuds EKS (`node_instance_types` dans `main.tf`)
- `t3.medium` pour le serveur k3s (`instance_type` dans `main.tf`)
- `multi_az = true` pour RDS
- `backup_retention_period = 7` pour les snapshots automatiques RDS

Ces paramètres sont volontairement dégradés pour ce TP uniquement.

---

## 10. Connecter kubectl à EKS

Une fois l'apply terminé, configure `kubectl` sur ta machine locale :

```bash
aws eks update-kubeconfig \
  --region eu-west-1 \
  --name capstone-staging-eks
```

Vérifie que tu vois bien les nœuds :
```bash
kubectl get nodes
# NAME                         STATUS   ROLES    AGE
# ip-10-0-1-xxx.ec2.internal   Ready    <none>   5m
# ip-10-0-4-xxx.ec2.internal   Ready    <none>   5m
```

---

## 11. Détruire (nettoyage, pour ne pas payer inutilement)

```bash
cd terraform/environments/staging
terraform destroy
# tape "yes"
```

Le bootstrap (bucket S3 + DynamoDB) n'est PAS détruit par cette commande
(protection `prevent_destroy`). Pour le supprimer manuellement :
```bash
cd terraform/bootstrap
terraform destroy -var="bucket_name=capstone-tfstate-igor-2026"
```

---

## 12. Problèmes rencontrés et solutions

| Erreur | Cause | Solution |
|---|---|---|
| `instance type not eligible for Free Tier` | `t3.medium` interdit en Free Tier | Passer `t3.micro` dans `main.tf` |
| `unsupported Kubernetes version` | Version EKS dépréciée | Passer à `1.31` dans `modules/eks/variables.tf` |
| `secret already scheduled for deletion` | Secret Manager garde les secrets 30j après destroy | `aws secretsmanager delete-secret --force-delete-without-recovery --secret-id <nom>` |
| `backup retention exceeds Free Tier` | RDS backups interdits en Free Tier | `backup_retention_period = 0` dans `modules/rds/main.tf` |
| `Module not installed` après ajout d'un module | `terraform init` pas relancé | `terraform init` puis `terraform plan` |