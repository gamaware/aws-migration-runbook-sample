variable "name" {
  description = "Name prefix for every resource in the module."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the replication instance."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; the replication instance reaches RDS and the Secrets Manager endpoint inside it."
  type        = string
}

variable "subnet_ids" {
  description = "Application subnets: they route to the data center over the VPN and reach Secrets Manager through its interface endpoint."
  type        = list(string)
}

variable "onprem_cidr" {
  description = "CIDR block of the data center; the replication instance reaches the source database inside it."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the replication instance storage, the endpoints and the credential secrets."
  type        = string
}

variable "instance_class" {
  description = "Replication instance class."
  type        = string
  default     = "dms.r6i.large"
}

variable "allocated_storage_gb" {
  description = "Replication instance storage for cached changes and task logs."
  type        = number
  default     = 200
}

variable "create_service_roles" {
  description = "Create dms-vpc-role and dms-cloudwatch-logs-role. Set false if the account already has them."
  type        = bool
  default     = true
}

variable "onprem_database" {
  description = "Source database in the data center (SRV-07)."
  type = object({
    server_name   = string
    port          = number
    database_name = string
  })
}

variable "rds_database" {
  description = "Target database on RDS."
  type = object({
    server_name   = string
    port          = number
    database_name = string
  })
}

variable "forward_task" {
  description = "Data center to RDS task, from plan/data-migration.yaml."
  type = object({
    id             = string
    migration_type = string
    table_mappings = string
    settings       = string
  })

  validation {
    condition     = var.forward_task.migration_type == "full-load-and-cdc"
    error_message = "The forward task must be full-load-and-cdc: a full load alone would need the write freeze to cover the whole copy."
  }
}

variable "reverse_task" {
  description = "RDS to data center task, from plan/data-migration.yaml. It only runs after cutover."
  type = object({
    id             = string
    migration_type = string
    table_mappings = string
    settings       = string
  })

  validation {
    condition     = var.reverse_task.migration_type == "cdc"
    error_message = "The reverse task must be cdc only: a full load would overwrite the rollback target."
  }
}
