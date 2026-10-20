# Out-of-band monitoring for EC2 nodes. In-cluster Prometheus can't tell you the
# cluster is dead, so CloudWatch watches the machines from outside.
#
# Noise control ("smart" alerting):
#  - Individual metric alarms have NO actions; only two composite alarms notify.
#  - "health" (status checks) = critical; "pressure" (CPU/mem/disk) = warning.
#  - The pressure alarm is suppressed while the health alarm is firing, so a dead
#    node produces one email, not five.

locals {
  prefix = "${var.name}-${var.environment}"
}

# ---------------------------------------------------------------- per-instance alarms

resource "aws_cloudwatch_metric_alarm" "status" {
  for_each = var.instances

  alarm_name          = "${local.prefix}-${each.key}-status-check"
  alarm_description   = "${each.key}: EC2 system or instance status check failing"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = var.instances

  alarm_name          = "${local.prefix}-${each.key}-cpu-high"
  alarm_description   = "${each.key}: CPU above ${var.cpu_threshold}% for 15 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_threshold
  treat_missing_data  = "notBreaching"
}

# The next two come from the CloudWatch agent (CWAgent namespace) installed by user-data.
resource "aws_cloudwatch_metric_alarm" "memory" {
  for_each = var.instances

  alarm_name          = "${local.prefix}-${each.key}-memory-high"
  alarm_description   = "${each.key}: memory above ${var.memory_threshold}% for 10 minutes"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = each.value }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_threshold
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "disk" {
  for_each = var.instances

  alarm_name          = "${local.prefix}-${each.key}-disk-high"
  alarm_description   = "${each.key}: root disk above ${var.disk_threshold}%"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = each.value, path = "/", fstype = "ext4" }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.disk_threshold
  treat_missing_data  = "notBreaching"
}

# ---------------------------------------------------------------- composite alarms (these notify)

resource "aws_cloudwatch_composite_alarm" "health" {
  alarm_name        = "${local.prefix}-node-health"
  alarm_description = "CRITICAL [${var.environment}] one or more nodes are failing EC2 status checks"
  alarm_rule        = join(" OR ", [for a in aws_cloudwatch_metric_alarm.status : "ALARM(\"${a.arn}\")"])

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

resource "aws_cloudwatch_composite_alarm" "pressure" {
  alarm_name        = "${local.prefix}-node-pressure"
  alarm_description = "WARNING [${var.environment}] node CPU, memory or disk is under pressure"
  alarm_rule = join(" OR ", concat(
    [for a in aws_cloudwatch_metric_alarm.cpu : "ALARM(\"${a.arn}\")"],
    [for a in aws_cloudwatch_metric_alarm.memory : "ALARM(\"${a.arn}\")"],
    [for a in aws_cloudwatch_metric_alarm.disk : "ALARM(\"${a.arn}\")"],
  ))

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  # Don't send "high CPU" while the node is already reported as broken.
  actions_suppressor {
    alarm            = aws_cloudwatch_composite_alarm.health.alarm_name
    extension_period = 300
    wait_period      = 120
  }
}

# ---------------------------------------------------------------- dashboard

data "aws_region" "current" {}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${local.prefix}-nodes"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "alarm", x = 0, y = 0, width = 24, height = 3
        properties = {
          title  = "Alarm status (${var.environment})"
          alarms = [aws_cloudwatch_composite_alarm.health.arn, aws_cloudwatch_composite_alarm.pressure.arn]
        }
      },
      {
        type = "metric", x = 0, y = 3, width = 8, height = 6
        properties = {
          title   = "CPU %"
          region  = data.aws_region.current.name
          stat    = "Average"
          period  = 300
          metrics = [for k, id in var.instances : ["AWS/EC2", "CPUUtilization", "InstanceId", id, { label = k }]]
        }
      },
      {
        type = "metric", x = 8, y = 3, width = 8, height = 6
        properties = {
          title   = "Memory %"
          region  = data.aws_region.current.name
          stat    = "Average"
          period  = 300
          metrics = [for k, id in var.instances : ["CWAgent", "mem_used_percent", "InstanceId", id, { label = k }]]
        }
      },
      {
        type = "metric", x = 16, y = 3, width = 8, height = 6
        properties = {
          title   = "Root disk %"
          region  = data.aws_region.current.name
          stat    = "Maximum"
          period  = 300
          metrics = [for k, id in var.instances : ["CWAgent", "disk_used_percent", "InstanceId", id, "path", "/", "fstype", "ext4", { label = k }]]
        }
      },
      {
        type = "metric", x = 0, y = 9, width = 24, height = 5
        properties = {
          title   = "Status check failures"
          region  = data.aws_region.current.name
          stat    = "Maximum"
          period  = 60
          metrics = [for k, id in var.instances : ["AWS/EC2", "StatusCheckFailed", "InstanceId", id, { label = k }]]
        }
      },
    ]
  })
}
