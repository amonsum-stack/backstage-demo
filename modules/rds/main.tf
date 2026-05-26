# RDS Postgres - Private Subnet Deployment

# Private Subnets — one per AZ, no route to internet

/*
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = data.aws_vpc.default_vpc.id
  cidr_block        = cidrsubnet(data.aws_vpc.default_vpc.cidr_block, 4, count.index + 10)
  availability_zone = "${var.aws_region}${["a", "b", "c"][count.index]}"

  tags = {
    Name = "eks-private-${["a", "b", "c"][count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.default_vpc.id

  tags = {
    Name = "eks-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
*/

variable "private_subnet_id" {}
variable "vpc_id" {}
variable "node_security_group_id" {}
variable "db_username" {}
variable "db_name" {}
variable "db_engine" {}
variable "engine_version" {}
variable "instance_class" {}

# DB Subnet Group — RDS requires subnets in at least 2 AZs

resource "aws_db_subnet_group" "postgres" {
  name        = "eks-postgres-subnet-group"
  description = "Private subnets for EKS RDS Postgres"
  subnet_ids  = var.private_subnet_id

  tags = {
    Name = "eks-postgres-subnet-group"
  }
}

# Security Group — only allow inbound 5432 from node security group

resource "aws_security_group" "rds" {
  name        = "eks-rds-sg"
  description = "Allow Postgres access from EKS worker nodes only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "eks-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  description                  = "Allow Postgres from EKS worker nodes"
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  description       = "Allow all outbound (for RDS to reach AWS services)"
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Random password for the RDS master user

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"
}

# Store credentials in AWS Secrets Manager

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "eks/postgres/credentials"
  description             = "RDS Postgres credentials for EKS demo cluster"
  recovery_window_in_days = 0 # Delete instantly if you terraform destroy the secret, not for production 

  tags = {
    Name = "eks-postgres-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = var.db_name
  })
}

# RDS Postgres Instance

resource "aws_db_instance" "postgres" {
  identifier = "eks-demo-postgres"

  engine         = var.db_engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = 20
  max_allocated_storage = 100 
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # No public access — only reachable from within the VPC
  publicly_accessible = false

  # Backups — minimal for a lab
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Don't take a final snapshot when destroying (lab environment)
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "eks-demo-postgres"
  }
}

# Outputs

output "rds_endpoint" {
  description = "RDS Postgres endpoint (host:port)"
  value       = "${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}"
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "rds_instance_identifier" {
  description = "Identifier of the RDS instance (used for CloudWatch alarms)"
  value       = aws_db_instance.postgres.identifier
}
