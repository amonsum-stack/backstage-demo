variable "cluster_name" {}
variable "cluster_role_arn" {}
variable "vpc_id" {}
variable "subnet_ids" {
  type = list(string)
}
variable "node_role_name" {}
# variable "additional_policy_name" {}
variable "additional_policy_arn" {}
variable "node_group_desired_capacity" {}
variable "node_group_max_size" {}
variable "node_group_min_size" {}
variable "ec2_instance_type" {}
variable "node_ami_id" {}

resource "aws_eks_cluster" "demo_eks" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = "1.35"

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  lifecycle {
    ignore_changes = [access_config, vpc_config]
  }
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.demo_eks.identity[0].oidc[0].issuer
}

output "NodeInstanceRole" {
  value = aws_iam_role.node_instance_role.arn
}

output "NodeSecurityGroup" {
  value = aws_security_group.node_security_group.id
}

output "NodeAutoScalingGroup" {
  value = aws_cloudformation_stack.autoscaling_group.outputs["NodeAutoScalingGroup"]
}


# Worker node SSH key pair

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "pem_file" {
  filename        = pathexpand("~/.ssh/eks-aws.pem")
  file_permission = "600"
  content         = tls_private_key.key_pair.private_key_pem
}

resource "aws_key_pair" "eks_kp" {
  key_name   = "eks_kp"
  public_key = trimspace(tls_private_key.key_pair.public_key_openssh)
}


# Worker node IAM role

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node_instance_role" {
  name               = var.node_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
  path               = "/"
}

resource "aws_iam_role_policy_attachment" "node_instance_role_secrets_manager" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.node_instance_role.name
}

resource "aws_iam_role_policy_attachment" "node_instance_role_EKSWNP" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_instance_role.name
}

resource "aws_iam_role_policy_attachment" "node_instance_role_EKSCNIP" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_instance_role.name
}

resource "aws_iam_role_policy_attachment" "node_instance_role_EKSCRRO" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_instance_role.name
}

resource "aws_iam_role_policy_attachment" "node_instance_role_SSMMIC" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_instance_role.name
}

# data "aws_iam_policy" "additional_policy" {
#  name = var.additional_policy_name
#}

resource "aws_iam_role_policy_attachment" "node_instance_role_loadbalancer" {
  policy_arn = var.additional_policy_arn
  role       = aws_iam_role.node_instance_role.name
}

# Cluster autoscaler IAM policy

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "eks-cluster-autoscaler"
  description = "Allows Cluster Autoscaler to manage the ASG"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeASG"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = ["*"]
      },
      {
        Sid    = "ModifyASG"
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.node_instance_role.name
}

# Instance profile

resource "aws_iam_instance_profile" "node_instance_profile" {
  name = "NodeInstanceProfile"
  path = "/"
  role = aws_iam_role.node_instance_role.id
}

# Node security group

resource "aws_security_group" "node_security_group" {
  name        = "NodeSecurityGroupIngress"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id

  tags = {
    "Name" = "NodeSecurityGroupIngress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "node_security_group_ingress" {
  description                  = "Allow node to communicate with each other"
  ip_protocol                  = "-1"
  security_group_id            = aws_security_group.node_security_group.id
  referenced_security_group_id = aws_security_group.node_security_group.id
}

resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  description       = "Allow node egress to anywhere"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  security_group_id = aws_security_group.node_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "node_security_group_from_control_plane_ingress" {
  description                  = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  security_group_id            = aws_security_group.node_security_group.id
  referenced_security_group_id = aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_egress_to_node_security_group_on_443" {
  description                  = "Allow pods running extension API servers on port 443 to receive communication from cluster control plane"
  security_group_id            = aws_security_group.node_security_group.id
  referenced_security_group_id = aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_control_plane_security_group_ingress" {
  description                  = "Allow pods to communicate with the cluster API Server"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
  referenced_security_group_id = aws_security_group.node_security_group.id
  security_group_id            = aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "control_plane_egress_to_node_security_group" {
  description                  = "Allow the cluster control plane to communicate with worker Kubelet and pods"
  referenced_security_group_id = aws_security_group.node_security_group.id
  security_group_id            = aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_egress_to_node_security_group_on_443" {
  description                  = "Allow the cluster control plane to communicate with pods running extension API servers on port 443"
  referenced_security_group_id = aws_security_group.node_security_group.id
  security_group_id            = aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
}


# Launch template + ASG via CloudFormation

resource "aws_launch_template" "node_launch_template" {
  name = "NodeLaunchTemplate"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      delete_on_termination = true
      volume_size           = 30
      volume_type           = "gp2"
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.node_instance_profile.name
  }

  key_name      = aws_key_pair.eks_kp.key_name
  instance_type = var.ec2_instance_type
  image_id      = var.node_ami_id

  vpc_security_group_ids = [
    aws_security_group.node_security_group.id
  ]

  metadata_options {
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
    http_tokens                 = "optional" # this should be set to requried in production for more security tokens
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                        = "worker-node"
      "k8s.io/cluster-autoscaler/enabled"         = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    }
  }

  tags = {
    "Name"                                        = "NodeLaunchTemplate"
    "k8s.io/cluster-autoscaler/enabled"           = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

user_data = base64encode(<<EOF
---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${var.cluster_name}
    apiServerEndpoint: ${aws_eks_cluster.demo_eks.endpoint}
    certificateAuthority: ${aws_eks_cluster.demo_eks.certificate_authority[0].data}
    cidr: ${aws_eks_cluster.demo_eks.kubernetes_network_config[0].service_ipv4_cidr}
  kubelet:
    config:
      maxPods: 110
EOF
  )
}

resource "time_sleep" "wait_30_seconds" {
  depends_on      = [aws_launch_template.node_launch_template]
  create_duration = "30s"
}

resource "aws_cloudformation_stack" "autoscaling_group" {
  depends_on = [time_sleep.wait_30_seconds]
  name       = "eks-cluster-stack"

  template_body = <<EOF
Description: "Node autoscaler"
Resources:
  NodeGroup:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      VPCZoneIdentifier: ["${var.subnet_ids[0]}","${var.subnet_ids[1]}","${var.subnet_ids[2]}"]
      MinSize: "${var.node_group_min_size}"
      MaxSize: "${var.node_group_max_size}"
      DesiredCapacity: "${var.node_group_desired_capacity}"
      HealthCheckType: EC2
      LaunchTemplate:
        LaunchTemplateId: "${aws_launch_template.node_launch_template.id}"
        Version: "${aws_launch_template.node_launch_template.latest_version}"
      Tags:
        - Key: "k8s.io/cluster-autoscaler/enabled"
          Value: "true"
          PropagateAtLaunch: true
        - Key: "k8s.io/cluster-autoscaler/${var.cluster_name}"
          Value: "owned"
          PropagateAtLaunch: true
    UpdatePolicy:
      AutoScalingScheduledAction:
        IgnoreUnmodifiedGroupSizeProperties: true
      AutoScalingRollingUpdate:
        MaxBatchSize: 1
        MinInstancesInService: "${var.node_group_desired_capacity}"
        PauseTime: PT5M
Outputs:
  NodeAutoScalingGroup:
    Description: The autoscaling group
    Value: !Ref NodeGroup
EOF

  lifecycle {
    ignore_changes = [template_body]
  }
}

output "node_security_group_id" {
  value = aws_security_group.node_security_group.id
}
