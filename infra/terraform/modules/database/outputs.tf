output "address" {
  description = "Host name of the RDS endpoint; the DMS target endpoint and the application connect to it."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "instance_identifier" {
  description = "RDS instance identifier, used in the runbook's CloudWatch checks."
  value       = aws_db_instance.this.identifier
}

output "security_group_id" {
  description = "Security group of the database."
  value       = aws_security_group.db.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret that RDS manages for the master user."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "onprem_client_cidrs" {
  description = "On-premises hosts admitted on 5432; tests compare it with the hybrid links in the plan."
  value       = sort([for r in aws_vpc_security_group_ingress_rule.from_onprem : r.cidr_ipv4])
}

output "publicly_accessible" {
  description = "Whether RDS gives the instance a public address; always false."
  value       = aws_db_instance.this.publicly_accessible
}
