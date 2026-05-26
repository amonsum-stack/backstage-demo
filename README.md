# Backstage on EKS

A production-style internal developer portal built with [Backstage](https://backstage.io), deployed on AWS EKS, with full IaaC via Terraform and self-service infrastructure provisioning for developers.

Built as a DevOps portfolio project demonstrating end-to-end platform engineering — from AWS infrastructure to developer experience.

---

## What this project demonstrates

| Area | Technologies |
|---|---|
| Container orchestration | AWS EKS, Kubernetes, CloudFormation ASG |
| Infrastructure as Code | Terraform (modular), AWS provider |
| Developer portal | Backstage, Software Catalog, TechDocs, Software Templates |
| GitOps | GitHub Actions, Terraform remote state |
| Security | IRSA, OIDC, AWS Secrets Manager, no static credentials |
| Observability | CloudWatch alarms, SNS notifications |
| Storage | RDS PostgreSQL, S3 (backups + TechDocs) |
| Networking | VPC, public/private subnets, NAT, ALB Controller |

---

## Architecture

```
Developer
    │
    ▼
Backstage Portal (port-forward)
    │
    ├── Software Catalog ──── catalog-info.yaml in each repo
    ├── TechDocs ──────────── S3 bucket (pre-built in CI)
    ├── Kubernetes plugin ──── read-only ClusterRole → EKS
    └── Software Templates ─── GitHub → Terraform → AWS
            │
            ▼
    EKS Cluster (us-east-1)
            │
            ├── Backstage Pod (IRSA → Secrets Manager, S3)
            ├── AWS Load Balancer Controller (IRSA)
            ├── External Secrets Operator
            └── worker nodes (t3.medium, ASG 1-4)
                    │
                    ▼
            RDS PostgreSQL (private subnet)
            S3 backup bucket (weekly pg_dump)
            S3 TechDocs bucket
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
│   ├── service.yaml                 # ClusterIP Service + ConfigMap
│   ├── k8s-plugin-rbac.yaml         # Read-only ClusterRole for K8s plugin
│   └── get-k8s-plugin-credentials.sh
├── templates/
│   └── create-s3-bucket/            # Backstage Software Template
│       ├── template.yaml
│       └── skeleton/                # Rendered and pushed to GitHub on create
│           ├── main.tf
│           ├── catalog-info.yaml
│           └── .github/workflows/terraform.yml
├── catalog-info.yaml                # Weather API service catalog entry
├── app-config.yaml                  # Backstage configuration
└── docs/                            # TechDocs source
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
kubectl get nodes   # verify cluster is reachable
```

### 3. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-operator --create-namespace
```

### 4. Create the GitHub token secret

```bash
kubectl create secret generic backstage-github-secret \
  --from-literal=GITHUB_TOKEN=ghp_xxxxxxxxxxxx \
  -n backstage
```

### 5. Update deployment.yaml

Fill in the IRSA role ARN from step 1:

```yaml
# manifests/deployment.yaml
annotations:
  eks.amazonaws.com/role-arn: <backstage_irsa_role_arn>
```

### 6. Get Kubernetes plugin credentials

```bash
kubectl apply -f manifests/k8s-plugin-rbac.yaml
chmod +x manifests/get-k8s-plugin-credentials.sh
./manifests/get-k8s-plugin-credentials.sh
```

Paste the three values (`K8S_API_URL`, `K8S_CA_DATA`, `K8S_SA_TOKEN`) into `manifests/deployment.yaml` as env vars.

### 7. Deploy Backstage

```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/external-secret.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/deployment.yaml
```

Verify the pod is running:

```bash
kubectl get pods -n backstage
kubectl logs -n backstage deployment/backstage
```

### 8. Access the portal

```bash
kubectl port-forward svc/backstage 7007:7007 -n backstage
```

Open [http://localhost:7007](http://localhost:7007)

---

## Self-service infrastructure (Software Templates)

Developers can provision AWS resources directly from the portal:

1. Open Backstage → **Create** → **Create S3 Bucket**
2. Fill in bucket name, environment, owner
3. Hit **Create**

The scaffolder will:
- Render the Terraform skeleton with the provided values
- Create a private GitHub repo
- Push the Terraform code and a GitHub Actions workflow
- Register the new resource in the Backstage catalog

On merge to `main` the GitHub Actions workflow runs `terraform apply` and the bucket is created in AWS.

---

## Rebuilding the Docker image

If you modify the Backstage app:

```bash
cd my-backstage
yarn install
yarn tsc
yarn build:all
yarn build-image --tag igior/backstage:latest
docker push igior/backstage:latest
kubectl rollout restart deployment/backstage -n backstage
```

---

## Cleanup

```bash
terraform destroy
```

> Note: `force_destroy = true` is set on all S3 buckets so they empty and delete cleanly.
