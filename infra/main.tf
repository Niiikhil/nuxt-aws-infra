# One static Nuxt site (`nuxi generate` output) on AWS:
#
#   visitor -> CloudFront (+ CloudFront Function: redirects, /about -> /about/index.html)
#           -> Origin Access Control -> private S3 bucket
#
# Custom domains (certificate + DNS) are in domain.tf.
# No servers, no Lambda, no IAM roles.

locals {
  name        = "${var.resource_prefix}-${var.project}-${var.environment}"
  bucket_name = coalesce(var.bucket_name, "${local.name}-${var.aws_account_id}")
  origin_id   = "s3-site"

  # Keys normalised the same way the function normalises the request path.
  redirects = { for from, to in var.redirects : (length(from) > 1 ? trimsuffix(from, "/") : from) => to }

  edge_function_code = templatefile("${path.module}/edge-function.js.tftpl", {
    redirects        = jsonencode(local.redirects)
    rewrite_to_index = var.spa_mode ? "false" : "true"
  })

  # Pre-rendered: a real 404. SPA: every unknown path goes to the client router.
  error_page = var.spa_mode ? { code = 200, path = "/200.html" } : { code = 404, path = "/404.html" }
}

# --- S3 bucket: private, encrypted, versioned ---------------------------------

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name

  lifecycle {
    # Holds the live site. Removing it from code must never delete it.
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.site]
}

# --- CloudFront ----------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.name}-oac"
  description                       = "CloudFront access to ${local.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "viewer_request" {
  name    = "${local.name}-viewer-request"
  runtime = "cloudfront-js-2.0"
  comment = "Redirects and index.html rewrites"
  publish = true
  code    = local.edge_function_code

  lifecycle {
    precondition {
      condition     = length(local.edge_function_code) <= 10240
      error_message = "The CloudFront Function would exceed 10 KB. Reduce the number of redirects."
    }
  }
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = local.name
  aliases             = var.domain_names
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = var.price_class
  web_acl_id          = var.web_acl_id
  wait_for_deployment = true

  origin {
    origin_id                = local.origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = var.cache_policy_id
    response_headers_policy_id = var.response_headers_policy_id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # S3 answers 404 for missing keys (ListBucket is granted below); 403 is
  # mapped as well in case a key is unreadable.
  dynamic "custom_error_response" {
    for_each = [403, 404]
    content {
      error_code            = custom_error_response.value
      response_code         = local.error_page.code
      response_page_path    = local.error_page.path
      error_caching_min_ttl = 10
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = local.certificate_arn == null
    acm_certificate_arn            = local.certificate_arn
    ssl_support_method             = local.certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = local.certificate_arn == null ? "TLSv1" : "TLSv1.2_2021"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(var.domain_names) == 0 || local.certificate_arn != null
      error_message = "DOMAIN_NAMES needs ROUTE53_ZONE_ID (certificate created for you) or ACM_CERTIFICATE_ARN (existing us-east-1 certificate)."
    }
  }
}

# --- Bucket policy: only this distribution may read ----------------------------

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  # Lets S3 answer 404 (not 403) for pages that don't exist.
  statement {
    sid       = "AllowCloudFrontList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}
