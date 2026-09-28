output "alb_dns_name" {
  description = "DNS name of the internal load balancer; the aws records in the private hosted zone alias to it."
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

output "network_exposure" {
  description = "What can reach the load balancer and where the tasks may connect; the tests assert none of it is the internet."
  value = {
    alb_internal      = aws_lb.this.internal
    alb_subnet_ids    = sort(tolist(aws_lb.this.subnets))
    ingress_cidrs     = sort(distinct(concat([for r in aws_vpc_security_group_ingress_rule.alb_https : r.cidr_ipv4], [for r in aws_vpc_security_group_ingress_rule.alb_http : r.cidr_ipv4])))
    egress_cidrs      = sort(distinct([for r in concat([aws_vpc_security_group_egress_rule.services_https_vpc, aws_vpc_security_group_egress_rule.services_postgres], values(aws_vpc_security_group_egress_rule.services_https_carrier)) : r.cidr_ipv4]))
    access_log_bucket = one(aws_lb.this.access_logs).bucket
  }
}
