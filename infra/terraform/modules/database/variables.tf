variable "name" {
  description = "Name prefix for every resource in the module."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the database."
  type        = string
}

variable "data_subnet_ids" {
  description = "Data subnets without an internet route, one per Availability Zone."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL major version. RDS picks the default minor and upgrades minors in the maintenance window."
  type        = string

  validation {
    condition     = can(regex("^1[4-9]$", var.engine_version))
    error_message = "engine_version must be a PostgreSQL major version from 14 to 19, without a minor."
  }
}

variable "instance_class" {
  description = "RDS instance class, sized in plan/target.yaml."
  type        = string
}

variable "allocated_storage_gb" {
  description = "Initial gp3 storage in GiB."
  type        = number
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number

  validation {
    condition     = var.max_allocated_storage_gb > var.allocated_storage_gb
    error_message = "max_allocated_storage_gb must exceed allocated_storage_gb, or RDS rejects the autoscaling setting."
  }
}

variable "multi_az" {
  description = "Run a synchronous standby in a second Availability Zone."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Automated backup retention in days. It replaces the nightly pg_dump to the backup NAS (JOB-03)."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Keep between 7 and 35 days of automated backups; the hypercare period alone lasts seven."
  }
}

variable "kms_key_arn" {
  description = "KMS key for storage, Performance Insights and the managed master user secret."
  type        = string
}

variable "client_security_group_ids" {
  description = "Security groups admitted on 5432 (ECS tasks, DMS replication instance)."
  type        = list(string)
}

variable "onprem_client_cidrs" {
  description = "On-premises hosts admitted on 5432 over the VPN, derived from the hybrid links in plan/waves.yaml."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.onprem_client_cidrs : endswith(c, "/32") && can(cidrhost(c, 0))])
    error_message = "On-premises clients must be single hosts (/32); a whole data center range is too broad."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the instance. Only a teardown of a test copy turns it off."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Only the live test sets it, so its teardown leaves nothing behind."
  type        = bool
  default     = false
}
