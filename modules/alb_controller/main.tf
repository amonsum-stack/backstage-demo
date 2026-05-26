variable "oidc_provider_arn" {}   
variable "oidc_provider_url" {}   
variable "loadbalancer_policy_arn" {}  

data "aws_iam_policy_document" "alb_controller_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller_irsa" {
  name               = "eks-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json
  tags = {
    Name = "eks-alb-controller-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller_irsa_policy" {
  policy_arn = var.loadbalancer_policy_arn
  role       = aws_iam_role.alb_controller_irsa.name
}

output "alb_controller_irsa_arn" {
  description = "IAM role ARN to annotate the aws-load-balancer-controller ServiceAccount with"
  value       = aws_iam_role.alb_controller_irsa.arn
}