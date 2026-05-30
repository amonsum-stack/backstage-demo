# Backstage on EKS

A production-style internal developer portal built with [Backstage](https://backstage.io), deployed on AWS EKS, with full IaC via Terraform and self-service infrastructure provisioning for developers.

---

## What this project demonstrates

| Area | Technologies |
|---|---|
| Container orchestration | AWS EKS, Kubernetes, CloudFormation ASG |
| Infrastructure as Code | Terraform (modular), AWS provider |
| Developer portal | Backstage, Software Catalog, TechDocs, Software Templates |
| GitOps | ArgoCD App of Apps, automated sync |
| Security | IRSA, OIDC, AWS Secrets Manager, no static credentials |
| Storage | RDS PostgreSQL, S3 (backups + TechDocs) |
| Networking | VPC, public/private subnets, NAT, ALB Controller |

---

## Architecture

```
Developer
    │
    ▼
Backstage Portal
    │
    ├── Software Catalog ──── catalog-info.yaml in each repo
    ├── TechDocs ──────────── S3 bucket
    ├── Kubernetes plugin ──── read-only ClusterRole → EKS
    └── Software Templates
            │
            ├── Create S3 Bucket ──── GitHub repo → Terraform → AWS
            └── Deploy to Kubernetes
                        │
                        ├── Creates service repo (manifests.yaml)
                        └── Opens PR to eks-gitops/apps/
                                    │
                                    ▼
                            ArgoCD root-app (watches apps/)
                                    │
                                    ▼
                            Child ArgoCD Application
                                    │
                                    ▼
                            Kubernetes Deployment + Service + HPA
```

---

## Repository structure

```
.
├── main.tf                          # Root Terraform module
├── variables.tf
├── terraform.tfvars
├── modules/
│   ├── network/                     # VPC, subnets, IGW, NAT
│   ├── eks/                         # EKS cluster, ASG, IAM, security groups
│   ├── cluster_role/                # EKS cluster IAM role
│   ├── oidc/                        # OIDC provider for IRSA
│   ├── alb_controller/              # ALB controller IRSA role
│   ├── policies/                    # LB + EBS CSI IAM policy
│   ├── rds/                         # RDS PostgreSQL, Secrets Manager
│   ├── s3_backup/                   # pg_dump backup bucket + IRSA
│   ├── s3_techdocs/                 # TechDocs S3 bucket
│   ├── backstage_irsa/              # Backstage pod IRSA role
│   ├── sns/                         # SNS alarm topics
│   └── cloudwatch_alarms/           # RDS CloudWatch alarms
├── manifests/
│   ├── namespace.yaml
│   ├── external-secret.yaml         # Pulls RDS creds from Secrets Manager
│   ├── deployment.yaml              # Backstage Deployment + ServiceAccount
│   ├── service.yaml                 # ClusterIP Service
│   ├── argocd-rbac.yaml             # ArgoCD RBAC config
│   ├── k8s-plugin-rbac.yaml         # Read-only ClusterRole for K8s plugin
│   └── get-k8s-plugin-credentials.sh
├── templates/
│   ├── create-s3-bucket/            # Template: provision S3 via Terraform
│   │   ├── template.yaml
│   │   └── skeleton/
│   │       ├── main.tf
│   │       ├── catalog-info.yaml
│   │       └── .github/workflows/terraform.yml
│   └── create-k8s-deployment/       # Template: deploy app via ArgoCD
│       ├── template.yaml
│       ├── skeleton/                # Pushed to service repo on create
│       │   ├── manifests.yaml       # Deployment, Service, HPA
│       │   ├── catalog-info.yaml
│       │   └── deploy.yml
│       └── argocd-skeleton/         # Pushed to eks-gitops/apps/ via PR
│           └── apps/
│               └── ${{ values.app_name }}.yaml
├── catalog-info.yaml
├── app-config.yaml
└── docs/
    ├── mkdocs.yml
    ├── index.md
    ├── architecture.md
    └── runbook.md
```

---

## Prerequisites

- AWS account with admin credentials
- Terraform >= 1.5
- kubectl
- Helm
- Docker
- Node.js 20 + Yarn 4 (for rebuilding the Backstage image)

---

## Deployment

### 1. Provision AWS infrastructure

```bash
terraform init
terraform apply
```

Note the outputs — you'll need them in later steps:

```bash
terraform output backstage_irsa_role_arn
terraform output techdocs_bucket_name
terraform output node_instance_role_arn
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --name eks-demo-cluster --region us-east-1
kubectl get nodes
```
Dont forget to modify and apply aws-auth-cm.yaml so the nodes get registered to the cluster

### 3. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-operator --create-namespace
```

### 4. Install ArgoCD

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --set configs.params."server\.insecure"=true
```

### 5. Create the ArgoCD root Application

This is the only ArgoCD resource you apply manually. All subsequent deployments
are managed automatically through the GitOps repo.

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/amonsum-stack/eks-gitops
    targetRevision: HEAD
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### 6. Create the GitHub token secret

```bash
kubectl create secret generic backstage-github-secret \
  --from-literal=GITHUB_TOKEN=ghp_xxxxxxxxxxxx \
  -n backstage
```

For Argocd to be automatically registered with your private repos, in the url place your name from github
```bash
kubectl create secret generic github-repo-creds \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/amonsum-stack \
  --from-literal=username=git \
  --from-literal=password=ghp_xxxxxxxxxxxx \
  --dry-run=client -o yaml | \
  kubectl apply -f -

kubectl label secret github-repo-creds \
  -n argocd \
  argocd.argoproj.io/secret-type=repo-creds
```

### 7. Update deployment.yaml

Fill in the IRSA role ARN from step 1:

```yaml
annotations:
  eks.amazonaws.com/role-arn: <backstage_irsa_role_arn>
```

### 8. Get Kubernetes plugin credentials

```bash
kubectl apply -f manifests/k8s-plugin-rbac.yaml
chmod +x manifests/get-k8s-plugin-credentials.sh
./manifests/get-k8s-plugin-credentials.sh
```

The script automatically populates `K8S_API_URL`, `K8S_CA_DATA`, and `K8S_SA_TOKEN`
placeholders in `deployment.yaml`.

### 9. Deploy Backstage

```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/external-secret.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/deployment.yaml
```

Verify:

```bash
kubectl get pods -n backstage
kubectl logs -n backstage deployment/backstage
```

### 10. Access the portal

```bash
kubectl port-forward svc/backstage 7007:7007 -n backstage
```

Open [http://localhost:7007](http://localhost:7007)

---

## Self-service templates

### Deploy to Kubernetes

Deploys any containerised app to the EKS cluster via ArgoCD:

1. Backstage → **Create** → **Deploy to Kubernetes**
2. Fill in app name, namespace, image, port, scaling, and resource limits
3. Hit **Create**

The scaffolder will:
- Create a private GitHub repo with `manifests.yaml` (Deployment, Service, HPA)
- Open a PR in `eks-gitops/apps/` with an ArgoCD Application manifest
- Register the service in the Backstage catalog

After merging the PR, ArgoCD automatically syncs the manifests to the cluster.

### Create S3 Bucket

Provisions an AWS S3 bucket via Terraform:

1. Backstage → **Create** → **Create S3 Bucket**
2. Fill in bucket name, environment, versioning, lifecycle policy
3. Hit **Create**

The scaffolder will:
- Create a private GitHub repo with Terraform code
- Push a GitHub Actions workflow that runs `terraform apply` on merge
- Register the new resource in the Backstage catalog

---

## Cleanup

```bash
terraform destroy
```

> `force_destroy = true` is set on all S3 buckets so they empty and delete cleanly.
