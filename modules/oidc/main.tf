variable "oidc_issuer_url" {
  description = "OIDC issuer URL from the EKS cluster"
}

data "tls_certificate" "eks_oidc" {
  url = var.oidc_issuer_url
}

# Register the cluster's OIDC endpoint as a trusted identity provider in IAM.
# This is what enables IRSA — pods can assume IAM roles via projected ServiceAccount tokens.
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = var.oidc_issuer_url

  tags = {
    Name = "eks-oidc-provider"
  }
}

# Extract the OIDC provider hostname (without https://) for use in trust policy conditions.
locals {
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks_oidc_provider.url, "https://", "")
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks_oidc_provider.arn
}

output "oidc_provider_url" {
  value = local.oidc_provider_url
}
