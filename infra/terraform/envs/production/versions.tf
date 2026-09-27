terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }

  # Partial configuration: bucket, key and region come from `terraform init -backend-config=...` so no account
  # detail lives in the repository. S3 native locking replaces the DynamoDB lock table.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
