# S3 Backup Bucket + IRSA for pg_dump CronJob
#
# This file sets up:
#   1. S3 bucket for RDS Postgres backups
#   2. Bucket versioning (protects against accidental overwrites)
#   3. Server-side encryption (AES256)
#   4. Lifecycle policy:
#        Standard → Glacier Instant Retrieval after 30 days
#        Glacier  → Delete after 365 days

variable "cluster_name" {}
variable "oidc_provider_url" {}
variable "oidc_provider_arn" {}

# S3 Bucket

resource "aws_s3_bucket" "db_backups" {
  bucket        = "${var.cluster_name}-db-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Allow terraform destroy to empty the bucket

  tags = {
    Name    = "eks-db-backups"
    Purpose = "RDS Postgres weekly pg_dump backups"
  }
}

resource "aws_s3_bucket_public_access_block" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning — protects against accidental overwrites/deletes
resource "aws_s3_bucket_versioning" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_s3_bucket_lifecycle_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    id     = "backup-lifecycle"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# IAM Policy — scoped to this bucket only
# Only allows what the backup CronJob actually needs:
#   - s3:PutObject  -> upload the backup file
#   - s3:ListBucket -> check existing backups / verify upload

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "backup_s3_policy" {
  name        = "eks-backup-s3-policy"
  description = "Allow pg_dump CronJob to write backups to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPutBackups"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"   
        ]
        Resource = "${aws_s3_bucket.db_backups.arn}/backups/*"
      },
      {
        Sid      = "AllowListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.db_backups.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["backups/*"]
          }
        }
      }
    ]
  })
}

# IRSA Role — goes to backup-job ServiceAccount in the weather namespace 

data "aws_iam_policy_document" "backup_assume_role" {
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
      values   = ["system:serviceaccount:weather:backup-job"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup_irsa" {
  name               = "eks-backup-irsa"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json

  tags = {
    Name = "eks-backup-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "backup_irsa_policy" {
  policy_arn = aws_iam_policy.backup_s3_policy.arn
  role       = aws_iam_role.backup_irsa.name
}

# S3 Event Notification — Backup Completion
variable "backup_sns_topic_arn" {}

resource "aws_sns_topic_policy" "backup_events_s3" {
  arn = var.backup_sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = var.backup_sns_topic_arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.db_backups.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "backup_notification" {
  bucket = aws_s3_bucket.db_backups.id
  topic {
    topic_arn  = var.backup_sns_topic_arn
    events     = ["s3:ObjectCreated:*"]
    filter_prefix = "backups/"
    filter_suffix = ".sql.gz"
  }

  depends_on = [aws_sns_topic_policy.backup_events_s3]
}

# Outputs

output "backup_bucket_name" {
  description = "S3 bucket name for database backups"
  value       = aws_s3_bucket.db_backups.id
}

 output "backup_irsa_role_arn" {
  description = "IAM role ARN to annotate the backup-job ServiceAccount with"
  value       = aws_iam_role.backup_irsa.arn
}

output "aws_s3_bucket_arn" {
  description = "ARN of the S3 bucket (for SNS topic policy)"
  value       = aws_s3_bucket.db_backups.arn
}


