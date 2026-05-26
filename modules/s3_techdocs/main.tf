variable "cluster_name" {
  description = "EKS cluster name — used to make the bucket name unique"
}

variable "backstage_irsa_role_arn" {
  description = "ARN of the Backstage IRSA role — granted read access to this bucket"
}

data "aws_caller_identity" "current" {}

# ── S3 Bucket ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "techdocs" {
  bucket        = "${var.cluster_name}-techdocs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true   # lab environment — allow clean terraform destroy

  tags = {
    Name    = "eks-techdocs"
    Purpose = "Backstage TechDocs static assets"
  }
}

resource "aws_s3_bucket_public_access_block" "techdocs" {
  bucket = aws_s3_bucket.techdocs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "techdocs" {
  bucket = aws_s3_bucket.techdocs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "techdocs" {
  bucket = aws_s3_bucket.techdocs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Bucket policy ─────────────────────────────────────────────────────────────
# Only the Backstage IRSA role can read from this bucket.
# The CI/CD pipeline that builds and uploads TechDocs will use its own
# IAM credentials (e.g. a GitHub Actions OIDC role) — add that ARN
# to the Principal list when you set up the pipeline.

resource "aws_s3_bucket_policy" "techdocs" {
  bucket = aws_s3_bucket.techdocs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBackstageRead"
        Effect = "Allow"
        Principal = {
          AWS = var.backstage_irsa_role_arn
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.techdocs.arn,
          "${aws_s3_bucket.techdocs.arn}/*"
        ]
      }
    ]
  })
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "techdocs_bucket_name" {
  description = "S3 bucket name for TechDocs — use in TECHDOCS_S3_BUCKET env var and backstage_irsa module"
  value       = aws_s3_bucket.techdocs.id
}

output "techdocs_bucket_arn" {
  description = "ARN of the TechDocs S3 bucket"
  value       = aws_s3_bucket.techdocs.arn
}
