variable "name" {
  description = "Name prefix for the Resolver endpoint and its security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the internal load balancer and the Resolver inbound endpoint; the private zones are associated with it."
  type        = string
}

variable "associated_vpc_ids" {
  description = "Other VPCs in the account that must resolve the records, such as the storefront VPC."
  type        = list(string)
  default     = []
}

variable "resolver_subnet_ids" {
  description = "Private subnets for the Resolver inbound endpoint, in at least two Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.resolver_subnet_ids) >= 2
    error_message = "A Resolver endpoint needs addresses in at least two subnets."
  }
}

variable "resolver_client_cidrs" {
  description = "Networks whose DNS servers forward the wave 1 names to the Resolver inbound endpoint (the corporate network)."
  type        = list(string)

  validation {
    condition     = length(var.resolver_client_cidrs) > 0 && alltrue([for c in var.resolver_client_cidrs : can(cidrhost(c, 0)) && !contains(["0.0.0.0/0", "::/0"], c)])
    error_message = "List the corporate DNS networks as valid CIDRs; never 0.0.0.0/0 or ::/0."
  }
}

variable "records" {
  description = "Records to switch, keyed by fully qualified name, with the on-premises address they point to today. Each name gets its own private hosted zone."
  type = map(object({
    onprem_ip = string
  }))
}

variable "alb_dns_name" {
  description = "DNS name of the internal load balancer the aws records alias to."
  type        = string
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the load balancer."
  type        = string
}

variable "onprem_ttl" {
  description = "TTL of the on-premises records. Low, so a switch or a rollback reaches clients within minutes."
  type        = number
  default     = 60

  validation {
    condition     = var.onprem_ttl >= 30 && var.onprem_ttl <= 300
    error_message = "Keep the TTL between 30 and 300 seconds during the migration; a longer TTL delays the rollback."
  }
}

variable "traffic_weights" {
  description = "Route 53 weights. The database has one writer, so exactly one side receives traffic (ADR 0003)."
  type = object({
    onprem = number
    aws    = number
  })
  default = {
    onprem = 100
    aws    = 0
  }

  validation {
    condition     = contains([0, 100], var.traffic_weights.onprem) && contains([0, 100], var.traffic_weights.aws)
    error_message = "Weights are 0 or 100. A split would send writes to two databases at once."
  }

  validation {
    condition     = var.traffic_weights.onprem + var.traffic_weights.aws == 100
    error_message = "Exactly one side must receive traffic: {onprem = 100, aws = 0} or {onprem = 0, aws = 100}."
  }
}
