# Terraform — Infrastructure AWS

## 1. Prérequis : créer un compte / utilisateur AWS avec accès programmatique

Si ce n'est pas déjà fait :

1. Va sur https://console.aws.amazon.com/iam/
2. Menu de gauche → "Users" → "Create user"
3. Donne un nom (ex: `terraform-deploy`)
4. Ne coche PAS "Provide user access to AWS Management Console" (on veut juste un accès programmatique, pas un login web)
5. Attache la policy `AdministratorAccess` (pour ce TP — en vrai projet on restreindrait les permissions)
6. Une fois l'utilisateur créé, va dans l'onglet "Security credentials" de cet utilisateur
7. "Create access key" → choisis "Command Line Interface (CLI)" → confirme
8. **Note immédiatement** la paire générée :
   - Access Key ID (ex: `AKIA...`)
   - Secret Access Key (ex: `wJalrX...`)

⚠️ Le Secret Access Key ne sera affiché qu'une seule fois. S'il est perdu, il faudra en régénérer un.

## 2. Installer la AWS CLI

### macOS
brew install awscli

### Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

### Windows
Télécharge et lance l'installeur : https://awscli.amazonaws.com/AWSCLIV2.msi

### Vérifier l'installation
aws --version

## 3. Configurer la AWS CLI avec tes clés

aws configure

Il va te demander 4 choses, une par une :
AWS Access Key ID [None]: AKIA...........         (collée depuis l'étape 1)
AWS Secret Access Key [None]: wJalrX..........     (collée depuis l'étape 1)
Default region name [None]: eu-west-1
Default output format [None]: json

Vérifie que ça fonctionne :
aws sts get-caller-identity

Tu dois voir s'afficher ton `UserId`, `Account`, et `Arn`. Si tu as une erreur,
tes clés sont mal saisies — relance `aws configure` pour les corriger.

⚠️ Ne commit JAMAIS ces clés dans Git. Elles sont stockées localement dans
`~/.aws/credentials`, hors de ce dépôt.

## 4. Installer Terraform

### macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

### Linux (Debian/Ubuntu)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

### Vérifier l'installation
terraform -version
# doit afficher >= 1.7.0

## 5. Structure du dossier

terraform/
├── bootstrap/          Crée le bucket S3 + table DynamoDB pour stocker
│                        le state Terraform à distance.
│                        À exécuter UNE SEULE FOIS. Son propre state à lui
│                        reste en local (pas de backend distant pour ce module,
│                        c'est lui qui crée le backend des autres).
│
├── modules/
│   └── vpc/             Module réutilisable décrivant le réseau :
│                         VPC, subnets, Internet Gateway, NAT Gateway, routes.
│                         N'est jamais exécuté seul, il est appelé depuis
│                         environments/.
│
└── environments/
    └── staging/         Point d'entrée réel. Instancie le module vpc
                          avec des valeurs concrètes (région, noms, AZ).
                          C'est CE dossier qu'on exécute avec terraform apply.

Pourquoi séparer `modules/` et `environments/` ? Le module `vpc/` ne contient
aucune valeur en dur (pas de région, pas de nom hardcodé) — il est générique.
`environments/staging/` lui donne les vraies valeurs. Plus tard, un dossier
`environments/prod/` pourra réutiliser le même module avec d'autres valeurs,
sans dupliquer le code.

## 6. Étape A — Bootstrap (créer le backend S3)

cd terraform/bootstrap
terraform init
terraform apply -var="bucket_name=capstone-tfstate-TONNOM"

Remplace `TONNOM` par quelque chose d'unique à toi (les noms de bucket S3
sont uniques sur toute la planète AWS, pas juste ton compte — ex:
`capstone-tfstate-igor-2026`).

Terraform va te demander confirmation, tape `yes`.

Note bien les deux valeurs affichées à la fin :
- `bucket_name` → tu en as besoin à l'étape suivante
- `dynamodb_table` → idem

## 7. Étape B — Déployer le VPC

cd terraform/environments/staging

Ouvre `backend.tf` et remplace les valeurs `bucket` et `dynamodb_table`
par celles obtenues à l'étape A.

cp terraform.tfvars.example terraform.tfvars
# ouvre terraform.tfvars et ajuste si besoin (région, AZ...)

terraform init
terraform plan      # affiche ce qui VA être créé, sans rien créer encore
terraform apply     # crée réellement les ressources, tape "yes" pour confirmer

## 8. Ce que ça crée concrètement

Une fois `apply` terminé, tu as sur AWS :

- 1 VPC
- 4 subnets :
  - 1 subnet public (10.0.0.0/24) — contiendra plus tard le NAT Gateway,
    et l'ALB / EC2 k3s
  - 1 subnet privé "compute" (10.0.1.0/24) — contiendra plus tard les
    nœuds EKS. A accès Internet sortant via la NAT Gateway (pour tirer
    des images Docker par ex.) mais n'est pas joignable depuis l'extérieur.
  - 2 subnets privés "data" (10.0.2.0/24 et 10.0.3.0/24, sur 2 AZ
    différentes) — contiendront RDS. Aucun accès Internet, ni entrant
    ni sortant : la base de données est totalement isolée.
- 1 Internet Gateway (point d'entrée/sortie Internet du VPC)
- 1 NAT Gateway dans le subnet public (permet au subnet privé compute de
  sortir vers Internet sans être exposé)
- Les tables de routage associées à chaque subnet

Tu peux vérifier dans la console AWS → VPC → Subnets, ou avec :
aws ec2 describe-subnets --filters "Name=tag:Name,Values=capstone-staging-*"

## 9. Détruire (nettoyage, pour ne pas payer pour rien)

cd terraform/environments/staging
terraform destroy
# tape "yes" pour confirmer

Le bootstrap (bucket S3 + DynamoDB) n'est PAS détruit par cette commande
(protection volontaire). Pour le supprimer manuellement plus tard :
cd terraform/bootstrap
terraform destroy -var="bucket_name=capstone-tfstate-TONNOM"

## 10. Avancement du projet

| Brique          | Statut     | Dossier              |
|------------------|------------|------------------------|
| Réseau (VPC)   | ✅ Fait    | modules/vpc/         |
| EKS                | À venir   | modules/eks/         |
| RDS                | À venir   | modules/rds/         |
| EC2 + k3s       | À venir   | modules/ec2-k3s/   |

Chaque nouveau module sera ajouté dans `environments/staging/main.tf`,
en réutilisant les outputs du VPC (`private_compute_subnet_id`,
`private_data_subnet_ids`, `public_subnet_id`).