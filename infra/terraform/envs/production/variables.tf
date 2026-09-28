variable "images" {
  description = "Container images by service, pinned by digest. CI writes them after it builds and scans each image."
  type        = map(string)

  validation {
    condition     = alltrue([for i in values(var.images) : can(regex("@sha256:[0-9a-f]{64}$", i))])
    error_message = "Pin every image by digest; the digest is what CI scanned."
  }
}

variable "traffic_weights" {
  description = "Route 53 weights for the wave 1 records. The runbook changes them at the DNS switch and on rollback."
  type = object({
    onprem = number
    aws    = number
  })
  default = {
    onprem = 100
    aws    = 0
  }
}

variable "create_dms_service_roles" {
  description = "Create the account-level dms-vpc-role and dms-cloudwatch-logs-role."
  type        = bool
  default     = true
}
