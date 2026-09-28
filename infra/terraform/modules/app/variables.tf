variable "name" {
  description = "Name prefix for every resource in the module."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the load balancer and the ECS services."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; tasks reach the database, the interface endpoints and the load balancer only inside it."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Private subnets for the internal Application Load Balancer, one per Availability Zone."
  type        = list(string)

  validation {
    condition     = length(var.alb_subnet_ids) >= 2
    error_message = "An Application Load Balancer needs subnets in at least two Availability Zones."
  }
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
  description = "Private client ranges allowed to reach the internal load balancer: the corporate network, peered VPCs and the VPC itself."
  type        = list(string)

  validation {
    condition     = length(var.alb_ingress_cidrs) > 0
    error_message = "List at least one client range; the load balancer has no default audience."
  }

  # RFC 1918 only: the load balancer is internal, so no client range may be public, let alone 0.0.0.0/0.
  validation {
    condition = alltrue([for c in var.alb_ingress_cidrs : try(anytrue([
      tonumber(split("/", c)[1]) >= 8 && cidrhost("${cidrhost(c, 0)}/8", 0) == "10.0.0.0",
      tonumber(split("/", c)[1]) >= 12 && cidrhost("${cidrhost(c, 0)}/12", 0) == "172.16.0.0",
      tonumber(split("/", c)[1]) >= 16 && cidrhost("${cidrhost(c, 0)}/16", 0) == "192.168.0.0",
    ]), false)])
    error_message = "Every client range must be an RFC 1918 CIDR (10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16)."
  }
}

variable "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint; the tasks pull ECR image layers from S3 through it."
  type        = string
}

variable "carrier_api_cidrs" {
  description = "Published addresses of the parcel carrier label API, reached through the NAT gateways."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.carrier_api_cidrs : can(cidrhost(c, 0)) && tonumber(split("/", c)[1]) >= 24])
    error_message = "Carrier ranges must be valid CIDRs of /24 or narrower; never open HTTPS egress to the internet."
  }
}

variable "access_logs" {
  description = "Central log archive bucket and prefix for the load balancer access logs. The bucket policy must allow the Elastic Load Balancing log delivery service."
  type = object({
    bucket = string
    prefix = string
  })

  validation {
    condition     = length(var.access_logs.bucket) > 0 && !strcontains(var.access_logs.prefix, "AWSLogs")
    error_message = "Name the log archive bucket; the prefix must not contain AWSLogs."
  }
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
