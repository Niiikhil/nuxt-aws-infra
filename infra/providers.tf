locals {
  tags = {
    Project     = var.project
    Environment = var.environment
    Repository  = var.repository
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id] # refuses to touch any other account

  default_tags {
    tags = local.tags
  }
}

# CloudFront certificates must live in us-east-1.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}
