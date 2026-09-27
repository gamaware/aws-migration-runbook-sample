provider "aws" {
  region = local.target.region

  default_tags {
    tags = {
      Project     = "harbor-goods-migration"
      Environment = "production"
      ManagedBy   = "terraform"
      Wave        = "1"
    }
  }
}
