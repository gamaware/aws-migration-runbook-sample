variable "name" {
  description = "Name prefix for every resource in the module."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the load balancer and the ECS services."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; tasks may reach the database only inside it."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the Application Load Balancer."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Private subnets for the ECS tasks."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener. It must cover every host name in var.services."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the container log groups."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the container log groups in days."
  type        = number
  default     = 365
}

variable "alb_ingress_cidrs" {
  description = "Client ranges allowed to reach the load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "default_service" {
  description = "Service that receives requests whose host name matches no rule."
  type        = string
  default     = "web"
}

variable "services" {
  description = "ECS services keyed by name. Each one replaces the source servers listed in plan/target.yaml."
  type = map(object({
    image             = string
    cpu               = number
    memory            = number
    desired_count     = number
    container_port    = number
    health_check_path = string
    host_name         = string
    environment       = optional(map(string), {})
    secrets           = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for s in values(var.services) : can(regex("@sha256:[0-9a-f]{64}$", s.image))])
    error_message = "Every image must be pinned by digest (repository@sha256:<64 hex>); tags such as :latest can change under a running cutover."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.desired_count >= 2])
    error_message = "Every service needs at least two tasks so one Availability Zone can fail."
  }
}
