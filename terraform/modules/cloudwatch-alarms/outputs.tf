output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "composite_alarm_names" {
  value = [aws_cloudwatch_composite_alarm.health.alarm_name, aws_cloudwatch_composite_alarm.pressure.alarm_name]
}
