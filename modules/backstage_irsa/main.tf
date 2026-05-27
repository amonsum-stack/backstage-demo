variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the oidc module"
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https://) from the oidc module"
}

variable "techdocs_bucket_name" {
  description = "Name of the S3 bucket used for TechDocs"
}

# Only the 'backstage' ServiceAccount in the 'backstage' namespace on this specific cluster can assume this role.
# same pattern used in modules/alb_controller and modules/s3_backup.

data "aws_iam_policy_document" "backstage_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:backstage:backstage"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backstage_irsa" {
  name               = "eks-backstage-irsa"
  assume_role_policy = data.aws_iam_policy_document.backstage_assume_role.json

  tags = {
    Name = "eks-backstage-irsa"
  }
}

# Permissions policy 
# RDS-Postgres should be modified since its not used in here, but the secret manager is used.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_policy" "backstage_policy" {
  name        = "eks-backstage-policy"
  description = "Allows Backstage pod to read Postgres credentials and serve TechDocs from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadPostgresSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:eks/postgres/credentials*"
      },
      {
        Sid    = "AllowTechDocsS3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.techdocs_bucket_name}",
          "arn:aws:s3:::${var.techdocs_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backstage_irsa_policy" {
  policy_arn = aws_iam_policy.backstage_policy.arn
  role       = aws_iam_role.backstage_irsa.name
}

output "backstage_irsa_role_arn" {
  description = "IAM role ARN to annotate the Backstage ServiceAccount with"
  value       = aws_iam_role.backstage_irsa.arn
}
