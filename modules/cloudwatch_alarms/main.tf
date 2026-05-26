####################################################################
#
# CloudWatch Alarms
#
# EKS Node Alarms (per EC2 instance via ASG):
#   - CPU utilization > 90% for 5 minutes
#   - EC2 status check failed
#
# RDS Alarms:
#   - CPU utilization > 90% for 5 minutes
#   - Free storage < 20% (< 4GB on 20GB disk)
#   - Database connections > 80% of max (db.t3.micro max = 60)
#   - RDS instance status check failed
#
####################################################################
/*

# High CPU across any node in the ASG
resource "aws_cloudwatch_metric_alarm" "eks_node_cpu_high" {
  alarm_name          = "eks-node-cpu-high"
  alarm_description   = "EKS worker node CPU utilization exceeded 90% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2        
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300      
  statistic           = "Maximum" # Goes for all nodes in ASG
  threshold           = 90
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_cloudformation_stack.autoscaling_group.outputs["NodeAutoScalingGroup"]
  }

  alarm_actions = [aws_sns_topic.eks_alarms.arn]
  ok_actions    = [aws_sns_topic.eks_alarms.arn]  

  tags = {
    Name = "eks-node-cpu-high"
  }
}

# EC2 status check failed — node is unhealthy
resource "aws_cloudwatch_metric_alarm" "eks_node_status_check" {
  alarm_name          = "eks-node-status-check-failed"
  alarm_description   = "EKS worker node failed EC2 status check — node may be unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_cloudformation_stack.autoscaling_group.outputs["NodeAutoScalingGroup"]
  }

  alarm_actions = [aws_sns_topic.eks_alarms.arn]
  ok_actions    = [aws_sns_topic.eks_alarms.arn]

  tags = {
    Name = "eks-node-status-check-failed"
  }
}
*/
# Node alarms are disabled since we are using prometheus and grafana for monitoring.

variable "instance_identifier" {}
variable "alarm_sns_topic_arn" {}
variable "ok_sns_topic_arn" {}

# RDS Alarms

# High CPU on RDS instance
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "rds-cpu-high"
  alarm_description   = "RDS Postgres CPU utilization exceeded 90% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.instance_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.ok_sns_topic_arn]

  tags = {
    Name = "rds-cpu-high"
  }
}

# Low free storage — alert at 4GB free (20% of 20GB)
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "rds-storage-low"
  alarm_description   = "RDS Postgres free storage below 4GB — consider expanding or cleaning up"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 4294967296 # in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.instance_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.ok_sns_topic_arn]

  tags = {
    Name = "rds-storage-low"
  }
}

# High connection count — db.t3.micro max_connections ~ 60
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "rds-connections-high"
  alarm_description   = "RDS Postgres connection count above 80% of maximum (48/60)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 48
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.instance_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.ok_sns_topic_arn]

  tags = {
    Name = "rds-connections-high"
  }
}

# RDS instance availability — fires if instance is not available
resource "aws_cloudwatch_metric_alarm" "rds_instance_down" {
  alarm_name          = "rds-instance-down"
  alarm_description   = "RDS Postgres instance is not available"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "SampleCount"
  threshold           = 1
  treat_missing_data  = "breaching" # If no data, treat as down

  dimensions = {
    DBInstanceIdentifier = var.instance_identifier
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.ok_sns_topic_arn]

  tags = {
    Name = "rds-instance-down"
  }
}
