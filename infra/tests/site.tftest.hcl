# `terraform test` in infra/ (also runs on every pull request). Uses a mocked AWS provider, so
# no credentials are needed and nothing is created.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::111111111111:function/nuxt-shop-dev-viewer-request" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::nuxt-shop-dev-111111111111" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::111111111111:distribution/EMOCK"
      domain_name    = "dmock.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:111111111111:certificate/mock"
      domain_validation_options = [
        { domain_name = "example.com", resource_record_name = "_a.example.com.", resource_record_type = "CNAME", resource_record_value = "_a.acm-validations.aws." },
        { domain_name = "www.example.com", resource_record_name = "_b.www.example.com.", resource_record_type = "CNAME", resource_record_value = "_b.acm-validations.aws." },
      ]
    }
  }
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/mock" }
  }
}

variables {
  project        = "shop"
  environment    = "dev"
  aws_account_id = "111111111111"
  aws_region     = "us-east-1"
}

run "prerendered_site_defaults" {
  command = apply

  assert {
    # The bucket id itself is mocked; the OAC description carries the computed name.
    condition     = aws_cloudfront_origin_access_control.site.description == "CloudFront access to nuxt-shop-dev-111111111111"
    error_message = "Default bucket name should be <name>-<account id>."
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var REWRITE_TO_INDEX = true;")
    error_message = "Pre-rendered sites need the index.html rewrite."
  }
  assert {
    condition     = alltrue([for e in aws_cloudfront_distribution.site.custom_error_response : e.response_code == 404 && e.response_page_path == "/404.html"])
    error_message = "Pre-rendered sites should serve /404.html with status 404."
  }
  assert {
    condition     = aws_cloudfront_distribution.site.viewer_certificate[0].cloudfront_default_certificate
    error_message = "No domains: should use the default CloudFront certificate."
  }
  assert {
    condition     = output.site_url == "https://dmock.cloudfront.net"
    error_message = "site_url should be the CloudFront domain when no custom domain is set."
  }
  assert {
    condition     = length(aws_acm_certificate.this) == 0 && length(aws_route53_record.alias) == 0
    error_message = "No domains: no certificate or DNS records."
  }
}

run "spa_mode_and_redirects" {
  command = apply

  variables {
    spa_mode  = true
    redirects = { "/old/" = "/new", "/" = "/home" }
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var REWRITE_TO_INDEX = false;")
    error_message = "SPA mode must not rewrite to index.html."
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, jsonencode({ "/old" = "/new", "/" = "/home" }))
    error_message = "Redirect keys should lose their trailing slash (except \"/\")."
  }
  assert {
    condition     = alltrue([for e in aws_cloudfront_distribution.site.custom_error_response : e.response_code == 200 && e.response_page_path == "/200.html"])
    error_message = "SPA mode should fall back to /200.html with status 200."
  }
}

run "route53_domain_creates_certificate_and_records" {
  command = apply

  variables {
    domain_names    = ["example.com", "www.example.com"]
    route53_zone_id = "ZMOCK"
  }

  assert {
    condition     = length(aws_acm_certificate.this) == 1 && length(aws_route53_record.validation) == 2
    error_message = "Should request one certificate and validate both names."
  }
  assert {
    condition     = toset(keys(aws_route53_record.alias)) == toset(["example.com/A", "example.com/AAAA", "www.example.com/A", "www.example.com/AAAA"])
    error_message = "Should create A and AAAA alias records per domain."
  }
  assert {
    condition     = aws_cloudfront_distribution.site.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:111111111111:certificate/mock"
    error_message = "Distribution should use the validated certificate."
  }
  assert {
    condition     = output.site_url == "https://example.com"
    error_message = "site_url should use the first custom domain."
  }
}

run "existing_certificate_external_dns" {
  command = apply

  variables {
    domain_names        = ["shop.example.org"]
    acm_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/existing"
  }

  assert {
    condition     = length(aws_acm_certificate.this) == 0 && length(aws_route53_record.alias) == 0
    error_message = "With a supplied certificate and no zone, nothing DNS-related is created."
  }
  assert {
    condition     = aws_cloudfront_distribution.site.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:111111111111:certificate/existing"
    error_message = "Should use the supplied certificate."
  }
}

run "domain_without_certificate_or_zone_is_rejected" {
  command = plan

  variables {
    domain_names = ["shop.example.org"]
  }

  expect_failures = [aws_cloudfront_distribution.site]
}

run "invalid_project_is_rejected" {
  command = plan

  variables {
    project = "Bad_Name"
  }

  expect_failures = [var.project]
}

run "custom_names_per_environment" {
  command = apply

  variables {
    bucket_name   = "mysite-prod-assets"
    resource_name = "mysite-prod"
  }

  assert {
    condition     = aws_s3_bucket.site.bucket == "mysite-prod-assets"
    error_message = "S3_BUCKET_NAME should set the bucket name."
  }
  assert {
    condition     = aws_cloudfront_function.viewer_request.name == "mysite-prod-viewer-request"
    error_message = "RESOURCE_NAME should name the CloudFront function."
  }
  assert {
    condition     = aws_cloudfront_origin_access_control.site.name == "mysite-prod-oac"
    error_message = "RESOURCE_NAME should name the access control."
  }
  assert {
    condition     = aws_cloudfront_distribution.site.comment == "mysite-prod" && aws_cloudfront_distribution.site.tags["Name"] == "mysite-prod"
    error_message = "RESOURCE_NAME should label the distribution."
  }
}

run "invalid_bucket_name_is_rejected" {
  command = plan

  variables {
    bucket_name = "My_Bucket"
  }

  expect_failures = [var.bucket_name]
}

run "invalid_resource_name_is_rejected" {
  command = plan

  variables {
    resource_name = "has spaces"
  }

  expect_failures = [var.resource_name]
}
