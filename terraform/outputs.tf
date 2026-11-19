output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_id" {
  value = module.network.public_subnet_id
}

output "private_subnet_id" {
  value = module.network.private_subnet_id
}

output "instance_id" {
  value = module.compute.instance_id
}

output "app_url" {
  value = "http://${module.compute.public_ip}"
}

output "alerts_topic_arn" {
  value = module.monitoring.alerts_topic_arn
}
