module "network" {
  source               = "./modules/network"
  vpc_cidr             = var.vpc_cidr
  vpc_name             = var.vpc_name
  cidr_subnet_public   = var.cidr_subnet_public
  cidr_subnet_private  = var.cidr_subnet_private
  us_availability_zone = var.us_availability_zone
}

module "additional_policies" {
  source                 = "./modules/policies"
  additional_policy_name = var.additional_policy_name
}

module "cluster_role" {
  source                 = "./modules/cluster_role"
  cluster_role_name      = var.cluster_role_name
  additional_policy_arns = [module.additional_policies.policy_arn]
}

module "eks" {
  source                      = "./modules/eks"
  cluster_name                = var.cluster_name
  cluster_role_arn            = module.cluster_role.cluster_role_arn
  vpc_id                      = module.network.vpc_id
  subnet_ids                  = module.network.public_subnet_id
  node_role_name              = var.node_role_name
  # additional_policy_name      = var.additional_policy_name
  additional_policy_arn       = module.additional_policies.policy_arn
  node_group_desired_capacity = var.node_group_desired_capacity
  node_group_max_size         = var.node_group_max_size
  node_group_min_size         = var.node_group_min_size
  ec2_instance_type           = var.ec2_instance_type
  node_ami_id                 = data.aws_ssm_parameter.node_ami.value

  depends_on = [module.cluster_role, module.additional_policies]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
    enableNetworkPolicy = "true"
  })

  depends_on = [module.eks]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.eks]
}

module "rds" {
  source                 = "./modules/rds"
  private_subnet_id      = module.network.private_subnet_id
  vpc_id                 = module.network.vpc_id
  node_security_group_id = module.eks.node_security_group_id
  db_username            = var.db_username
  db_name                = var.db_name
  db_engine              = var.db_engine
  engine_version         = var.engine_version
  instance_class         = var.instance_class
}

module "cloudwatch" {
  source              = "./modules/cloudwatch_alarms"
  instance_identifier = module.rds.rds_instance_identifier
  alarm_sns_topic_arn = module.sns.sns_rds_alarms_arn
  ok_sns_topic_arn    = module.sns.sns_rds_alarms_arn
}

module "sns" {
  source = "./modules/sns"
  alert_email = var.alert_email
  # aws_s3_bucket_arn = module.s3_backup.aws_s3_bucket_arn
}

module "s3_backup" {
  source               = "./modules/s3_backup"
  cluster_name         = var.cluster_name
  oidc_provider_url    = module.oidc.oidc_provider_url
  oidc_provider_arn    = module.oidc.oidc_provider_arn
  backup_sns_topic_arn = module.sns.sns_backup_events_arn
}

module "oidc" {
  source            = "./modules/oidc"
  oidc_issuer_url   = module.eks.oidc_issuer_url

  depends_on = [module.eks]
}

module "alb_controller" {
  source                  = "./modules/alb_controller"
  oidc_provider_arn       = module.oidc.oidc_provider_arn
  oidc_provider_url       = module.oidc.oidc_provider_url
  loadbalancer_policy_arn = module.additional_policies.policy_arn

  depends_on = [module.oidc]
}

data "aws_ssm_parameter" "node_ami" {
  name = "/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

output "node_instance_role_arn" {
  value = module.eks.NodeInstanceRole
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_controller_irsa_arn" {
  value = module.alb_controller.alb_controller_irsa_arn
}

output "backup_irsa_role_arn" {
  value = module.s3_backup.backup_irsa_role_arn
}

output "backup_bucket_name" {
  value = module.s3_backup.backup_bucket_name
}

