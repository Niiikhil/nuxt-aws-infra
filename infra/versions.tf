terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration. The pipeline supplies:
  #   bucket = <prefix>-tfstate-<account id>-<region>   (made by bootstrap)
  #   key    = <project>/<environment>/terraform.tfstate
  #   region = <AWS_REGION>
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
