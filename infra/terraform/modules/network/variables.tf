variable "name" {
  description = "Name prefix for every resource in the module."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the target VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR of /20 or larger so each tier gets one /24 per Availability Zone."
  }
}

variable "azs" {
  description = "Availability Zones to spread the public, application and data subnets across."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Use two or three Availability Zones."
  }
}

variable "onprem_cidr" {
  description = "CIDR block of the on-premises data center reached through the Site-to-Site VPN."
  type        = string

  validation {
    condition = can(cidrhost(var.onprem_cidr, 0)) && (
      cidrhost("${cidrhost(var.onprem_cidr, 0)}/${min(tonumber(split("/", var.onprem_cidr)[1]), tonumber(split("/", var.vpc_cidr)[1]))}", 0)
      != cidrhost("${cidrhost(var.vpc_cidr, 0)}/${min(tonumber(split("/", var.onprem_cidr)[1]), tonumber(split("/", var.vpc_cidr)[1]))}", 0)
    )
    error_message = "onprem_cidr must be a valid CIDR that does not overlap vpc_cidr; overlapping ranges break VPN routing."
  }
}

variable "vpn_peer_ip" {
  description = "Public IP of the on-premises VPN device (customer gateway)."
  type        = string

  validation {
    condition     = can(cidrhost("${var.vpn_peer_ip}/32", 0))
    error_message = "vpn_peer_ip must be an IPv4 address."
  }
}

variable "vpn_bgp_asn" {
  description = "BGP ASN of the customer gateway. The tunnels use static routes; AWS still requires an ASN."
  type        = number
  default     = 65000
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the VPC flow log group."
  type        = string
}

variable "flow_log_retention_days" {
  description = "Retention of the VPC flow log group in days."
  type        = number
  default     = 365
}
