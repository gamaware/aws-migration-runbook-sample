output "replication_instance_arn" {
  description = "ARN of the replication instance."
  value       = aws_dms_replication_instance.this.replication_instance_arn
}

output "security_group_id" {
  description = "Security group of the replication instance; the database admits it on 5432."
  value       = aws_security_group.dms.id
}

output "forward_task_id" {
  description = "Identifier of the full load and CDC task; the runbook starts and monitors it by this name."
  value       = aws_dms_replication_task.forward.replication_task_id
}

output "reverse_task_id" {
  description = "Identifier of the reverse CDC task that keeps the data center current after cutover."
  value       = aws_dms_replication_task.reverse.replication_task_id
}

output "credential_secrets" {
  description = "Secrets the DBA fills before the full load: host, port, username and password as JSON keys."
  value = {
    onprem = { arn = aws_secretsmanager_secret.onprem.arn, host = var.onprem_database.server_name, port = var.onprem_database.port }
    rds    = { arn = aws_secretsmanager_secret.rds.arn, host = var.rds_database.server_name, port = var.rds_database.port }
  }
}
