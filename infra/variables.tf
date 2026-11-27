# -----------------------------------------------------------------------------
# Set automatically by the pipeline. Nothing to configure.
# -----------------------------------------------------------------------------

variable "project" {
  description = "Project slug. The pipeline uses PROJECT_NAME, or the repository name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,22}[a-z0-9]$", var.project))
    error_message = "project must be 2-24 characters: lowercase letters, digits, hyphens."
  }
}

variable "environment" {
  description = "dev, staging, production, ..."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,11}$", var.environment))
    error_message = "environment must be 1-12 characters: lowercase letters, digits, hyphens."
  }
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "repository" {
  description = "owner/repo, used for tags."
  type        = string
  default     = ""
}

variable "resource_prefix" {
  description = "Prefix for default resource names (when S3_BUCKET_NAME / RESOURCE_NAME aren't set) and the state bucket. Must match ResourcePrefix in the bootstrap stack."
  type        = string
  default     = "nuxt"
}

# -----------------------------------------------------------------------------
# Optional site settings. Set them as GitHub variables (see README), or in
# infra/env/<environment>.tfvars.
# -----------------------------------------------------------------------------

variable "domain_names" {
  description = "Custom domains. GitHub variable DOMAIN_NAMES, comma-separated. Empty = *.cloudfront.net only."
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "GitHub variable ROUTE53_ZONE_ID. With domain_names: creates + validates the certificate and the DNS records."
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "GitHub variable ACM_CERTIFICATE_ARN. An existing us-east-1 certificate, for DNS hosted outside Route 53."
  type        = string
  default     = null
}

variable "spa_mode" {
  description = "GitHub variable SPA_MODE=true for `ssr: false` apps: unknown paths serve /200.html with status 200."
  type        = bool
  default     = false
}

variable "redirects" {
  description = "GitHub variable REDIRECTS, JSON: {\"/old\":\"/new\"}. 301 at the edge; the query string is dropped. Keep under ~100 entries (10 KB function limit)."
  type        = map(string)
  default     = {}
}

variable "price_class" {
  description = "GitHub variable PRICE_CLASS: PriceClass_100 (NA/EU), PriceClass_200, PriceClass_All. Applied when the distribution is created; change it later in the console (or via a pricing plan)."
  type        = string
  default     = "PriceClass_100"
}

variable "web_acl_id" {
  description = "GitHub variable WEB_ACL_ID: a CLOUDFRONT-scope WAF ACL ARN. Applied when the distribution is created; afterwards manage it in the console (pricing plans attach their own)."
  type        = string
  default     = null
}

variable "cache_policy_id" {
  description = "Default: AWS managed CachingOptimized, which honours the Cache-Control headers set at upload."
  type        = string
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

variable "response_headers_policy_id" {
  description = "Default: AWS managed SecurityHeadersPolicy. null for none."
  type        = string
  default     = "67f7725c-6f97-4210-82d7-5512b31e9d03"
}

variable "noncurrent_version_expiration_days" {
  description = "How long replaced/deleted site files are kept, for rollback."
  type        = number
  default     = 30
}

variable "adopt" {
  description = <<-EOT
    Existing resources to take over instead of creating (see imports.tf).
    GitHub variable TF_VAR_adopt, e.g. {"distribution_id":"E123ABC"}.
    An adopted bucket must also be named via S3_BUCKET_NAME.
  EOT
  type = object({
    bucket_name              = optional(string)
    distribution_id          = optional(string)
    origin_access_control_id = optional(string)
  })
  default = {}
}

# --- Names (GitHub environment variables S3_BUCKET_NAME / RESOURCE_NAME) -------
# Set these BEFORE an environment's first deploy. Changing them later means
# new resources, which the safety checks block (see README).

variable "bucket_name" {
  description = "S3 bucket name (GitHub variable S3_BUCKET_NAME). Globally unique across all AWS accounts. Default: <prefix>-<project>-<env>-<account id>."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "S3_BUCKET_NAME must be 3-63 characters: lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_name" {
  description = "Base name for the CloudFront function (<name>-viewer-request), access control (<name>-oac) and the distribution's comment/Name tag (GitHub variable RESOURCE_NAME). Default: <prefix>-<project>-<env>."
  type        = string
  default     = null

  validation {
    condition     = var.resource_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{1,46}[a-zA-Z0-9]$", var.resource_name))
    error_message = "RESOURCE_NAME must be 3-48 characters: letters, digits, hyphens and underscores."
  }
}
