# Module monitoring : alertes SNS (e-mail) + alarmes CloudWatch sur l'instance applicative.

data "aws_region" "current" {}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# Abonnement e-mail créé seulement si une adresse est fournie (AWS envoie un lien de confirmation)
resource "aws_sns_topic_subscription" "email" {
  count     = try(length(var.alert_email), 0) > 0 ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CPU > seuil pendant 2 x 5 minutes
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "CPU de l'instance TaskOps au-dessus de ${var.cpu_threshold} % pendant 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions          = { InstanceId = var.instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Panne matérielle AWS : alerte + récupération automatique de l'instance sur un autre hôte
resource "aws_cloudwatch_metric_alarm" "system_check" {
  alarm_name          = "${var.name}-system-check-failed"
  alarm_description   = "Échec du contrôle système AWS : récupération automatique de l'instance"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  dimensions          = { InstanceId = var.instance_id }
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.region}:ec2:recover", aws_sns_topic.alerts.arn]
}
