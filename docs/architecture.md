# Architecture

## Infrastructure

The Weather API runs as a Kubernetes Deployment on EKS in the `weather` namespace.

```
┌─────────────────────────────────────┐
│           EKS Cluster               │
│                                     │
│  ┌──────────────┐                   │
│  │  weather-api │                   │
│  │  Deployment  │──── IRSA ────────►│ Secrets Manager
│  │  (2 replicas)│                   │ S3 (backups)
│  └──────┬───────┘                   │
│         │                           │
└─────────┼───────────────────────────┘
          │
          ▼
   RDS PostgreSQL
   (private subnet)
```

## IRSA

The pod uses IAM Roles for Service Accounts (IRSA) to access AWS services
without storing credentials. The role is provisioned by the `backstage_irsa`
Terraform module.
