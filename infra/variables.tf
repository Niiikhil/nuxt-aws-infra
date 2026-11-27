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
  description = "Prefix on every resource name. Must match ResourcePrefix in the bootstrap stack (the deploy role is limited to it)."
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
  description = "GitHub variable PRICE_CLASS: PriceClass_100 (NA/EU), PriceClass_200, PriceClass_All."
  type        = string
  default     = "PriceClass_100"
}

variable "web_acl_id" {
  description = "GitHub variable WEB_ACL_ID: a CLOUDFRONT-scope WAF ACL ARN."
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
    An adopted bucket must also be named via TF_VAR_bucket_name.
  EOT
  type = object({
    bucket_name              = optional(string)
    distribution_id          = optional(string)
    origin_access_control_id = optional(string)
  })
  default = {}
}

variable "bucket_name" {
  description = "Override the bucket name (only when adopting). Default: <prefix>-<project>-<env>-<account id>."
  type        = string
  default     = null
}
