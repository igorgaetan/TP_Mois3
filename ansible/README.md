# Ansible — Configuration du serveur k3s

Ce dossier configure la VM EC2 créée par Terraform (`modules/ec2-k3s`) : il
installe k3s dessus puis déploie l'application. Il n'intervient PAS sur EKS
(AWS gère la configuration des nœuds EKS lui-même — voir le README principal
pour l'explication complète).

---

## 1. Prérequis

Avant de commencer, tu dois avoir :
- Terraform déjà appliqué (`terraform apply` dans `terraform/environments/staging`)
  terminé avec succès, en particulier la sortie `k3s_public_ip`
- Ta clé SSH privée disponible (`~/.ssh/capstone_k3s`), celle générée à
  l'étape Terraform

Vérifie que Terraform a bien créé l'IP :
```bash
cd terraform/environments/staging
terraform output k3s_public_ip
```

## 2. Installer Python (si pas déjà fait)

Ansible est écrit en Python et nécessite Python 3 sur ta machine locale.

### Vérifier si tu l'as déjà
```bash
python3 --version
```
Si tu vois un numéro de version (3.9+), passe à l'étape suivante.

### Linux (Debian/Ubuntu)
```bash
sudo apt update
sudo apt install python3 python3-pip python3-venv
```

### macOS
```bash
brew install python3
```

## 3. Créer un environnement virtuel Python (bonne pratique)

On isole les paquets Ansible du reste du système pour éviter les conflits :

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
```

Tu dois voir `(.venv)` apparaître au début de ton invite de commande.

⚠️ À chaque fois que tu ouvres un nouveau terminal pour travailler sur Ansible,
relance `source .venv/bin/activate` pour réactiver l'environnement. `deactivate`

## 4. Installer Ansible

```bash
pip install --upgrade pip
pip install ansible
```

Vérifie l'installation :
```bash
ansible --version
# doit afficher ansible [core 2.15+] ou supérieur
```

## 5. Installer les collections Ansible nécessaires

Ansible "de base" ne sait pas parler à AWS ni à Kubernetes/Helm nativement —
on a besoin de collections additionnelles :

```bash
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install community.general
```

`amazon.aws` permet l'inventaire dynamique (lire la liste des EC2 directement
depuis AWS). `kubernetes.core` permet d'installer des charts Helm sur le
cluster k3s une fois créé.

## 6. Installer boto3 (dépendance Python pour parler à AWS)

```bash
pip install boto3 botocore
```

Sans ça, le plugin d'inventaire `amazon.aws.aws_ec2` ne fonctionnera pas.

## 7. Vérifier que tes credentials AWS sont toujours actifs

Ansible réutilise les mêmes credentials que Terraform et la CLI AWS
(configurés via `aws configure` au tout début du TP) :

```bash
aws sts get-caller-identity
```

Si ça répond avec ton `Account` et `Arn`, tu es prêt.

## 8. Structure du dossier

```
ansible/
├── inventory/
│   └── aws_ec2.yml       Inventaire DYNAMIQUE : interroge AWS directement
│                          au lieu d'une liste d'IP en dur. Trouve l'EC2 grâce
│                          au tag Role=k3s posé par Terraform.
│
├── roles/
│   ├── k3s-install/       Installe k3s sur la VM, récupère le kubeconfig,
│   │                       installe nginx-ingress via Helm.
│   └── k3s-deploy-app/    (à venir) Récupère les secrets RDS depuis AWS
│                           Secrets Manager et déploie l'app sur k3s.
│
├── ansible.cfg            Config par défaut (inventaire, user SSH, clé...)
└── playbook-k3s.yml        Point d'entrée : applique les rôles à l'hôte k3s.
```

## 9. Vérifier que l'inventaire dynamique trouve bien ta VM

```bash
ansible-inventory -i inventory/aws_ec2.yml --graph
```

Tu dois voir une sortie avec un groupe `tag_k3s` contenant une IP — celle
de la VM créée par Terraform. Si le groupe est vide :
- Vérifie que `terraform apply` est bien terminé (`terraform output k3s_public_ip`)
- Vérifie que tu es dans la bonne région AWS (`eu-west-1` dans `inventory/aws_ec2.yml`)
- Attends 1-2 minutes, le tagging AWS peut avoir un léger délai de propagation

## 10. Tester la connexion SSH manuellement (sanity check)

Avant de lancer Ansible, vérifie que tu peux te connecter toi-même :

```bash
ssh -i ~/.ssh/capstone_k3s ubuntu@$(terraform -chdir=../terraform/environments/staging output -raw k3s_public_ip)
```

Si ça fonctionne (tu arrives sur un prompt Ubuntu), tape `exit` et continue.
Si ça échoue avec "Connection refused" ou timeout :
- Vérifie que ton IP publique n'a pas changé (`curl ifconfig.me`) — si oui,
  il faut mettre à jour `allowed_ssh_cidr` dans `terraform.tfvars` et
  relancer `terraform apply`
- Attends quelques minutes, l'instance EC2 peut encore être en train de démarrer

## 11. Lancer le playbook

```bash
ansible-playbook playbook-k3s.yml
```

Ce que ça fait, dans l'ordre :
1. Installe k3s sur la VM (script officiel Rancher)
2. Attend que le cluster soit prêt
3. Rapatrie le `kubeconfig` sur ta machine locale (fichier `kubeconfig-k3s.yaml`,
   créé dans `ansible/`)
4. Installe nginx-ingress via Helm sur le cluster k3s fraîchement créé

## 12. Vérifier que ça a fonctionné

Une fois le playbook terminé sans erreur :

```bash
export KUBECONFIG=./kubeconfig-k3s.yaml
kubectl get nodes
```

Tu dois voir 1 nœud en état `Ready`.

```bash
kubectl get pods -n ingress-nginx
```

Tu dois voir les pods nginx-ingress en état `Running`.

## 13. Relancer le playbook après modification

Ansible est idempotent : tu peux relancer `ansible-playbook playbook-k3s.yml`
autant de fois que tu veux, il ne réinstalle pas ce qui existe déjà
(`creates: /usr/local/bin/k3s` empêche la réinstallation de k3s par exemple).

## 14. Problèmes courants

| Symptôme | Cause probable | Solution |
|---|---|---|
| `UNREACHABLE` / timeout SSH | IP publique changée depuis le dernier `terraform apply` | Relancer `curl ifconfig.me`, mettre à jour `allowed_ssh_cidr`, `terraform apply` |
| Inventaire vide (`tag_k3s` absent) | Terraform pas encore appliqué, ou mauvaise région | Vérifier `terraform output`, vérifier la région dans `aws_ec2.yml` |
| `Permission denied (publickey)` | Mauvais chemin de clé privée | Vérifier `private_key_file` dans `ansible.cfg` |
| Module `amazon.aws.aws_ec2` introuvable | Collection non installée | `ansible-galaxy collection install amazon.aws` |

## 15. Avancement

| Étape | Statut |
|---|---|
| Inventaire dynamique AWS | ✅ Fait |
| Installation k3s | ✅ Fait |
| Installation nginx-ingress | ✅ Fait |
| Déploiement app (secrets RDS + kubectl apply) | À venir, une fois RDS confirmé |
