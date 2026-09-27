variable "zone_id" {
  description = "Route 53 hosted zone that holds the records (example.com)."
  type        = string
}

variable "records" {
  description = "Records to switch, keyed by fully qualified name, with the on-premises address they point to today."
  type = map(object({
    onprem_ip = string
  }))
}

variable "alb_dns_name" {
  description = "DNS name of the load balancer the aws records alias to."
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
