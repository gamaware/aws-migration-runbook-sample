variable "aws_profile" {
  description = "Named AWS CLI profile of the sandbox account. The live test never uses a default profile."
  type        = string
}

variable "region" {
  description = "Region of the live test."
  type        = string
  default     = "us-east-1"
}

variable "run_id" {
  description = "Suffix that keeps names unique per run, set by scripts/test_live.sh."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.run_id))
    error_message = "run_id must be 4 to 12 lowercase letters or digits."
  }
}
