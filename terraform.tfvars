vpc_cidr = "10.0.0.0/16"

vpc_name = "test-vpc"

cidr_subnet_public = ["10.0.1.0/24", "10.0.5.0/24", "10.0.6.0/24"]

cidr_subnet_private = ["10.0.2.0/24", "10.0.3.0/24", "10.0.4.0/24"]

us_availability_zone = ["us-east-1a", "us-east-1b", "us-east-1c"]

cluster_name = "eks-demo-cluster"

cluster_role_name = "eksClusterRole"

node_role_name = "eksWorkerNodeRole"

additional_policy_name = "eksPolicy"

node_group_desired_capacity = 3

node_group_max_size = 4

node_group_min_size = 1

ec2_instance_type = "t3.medium"

db_username = "postgres"

db_name = "postgres_db"

db_engine = "postgres"

engine_version = "16.9"

instance_class = "db.t3.micro"

alert_email = "example@company.com"