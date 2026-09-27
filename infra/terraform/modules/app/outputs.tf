output "alb_dns_name" {
  description = "DNS name of the load balancer; the Route 53 aws records alias to it."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer, needed for alias records."
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  description = "ARN suffix of the load balancer, used in CloudWatch metric queries during cutover."
  value       = aws_lb.this.arn_suffix
}

output "service_security_group_id" {
  description = "Security group of the ECS tasks; the database admits it on 5432."
  value       = aws_security_group.services.id
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_names" {
  description = "ECS service names keyed by service."
  value       = { for k, s in aws_ecs_service.this : k => s.name }
}
