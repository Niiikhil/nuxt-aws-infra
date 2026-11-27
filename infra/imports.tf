# Taking over resources that already exist in AWS.
#
# You normally don't need this: Terraform remembers what it created (in the
# state bucket), so re-running the pipeline never creates anything twice.
# These blocks are for a site that was set up BEFORE this pipeline, by hand.
#
# Set the GitHub variable TF_VAR_adopt on that environment, e.g.
#   {"bucket_name":"old-bucket","distribution_id":"E1234567890ABC"}
# and TF_VAR_bucket_name = old-bucket. The deploy log then shows "to import".
# The bucket name must start with the resource prefix ("nuxt-"), or the
# deploy role won't be allowed to manage it.

import {
  for_each = var.adopt.bucket_name == null ? {} : { this = var.adopt.bucket_name }
  to       = aws_s3_bucket.site
  id       = each.value
}

import {
  for_each = var.adopt.distribution_id == null ? {} : { this = var.adopt.distribution_id }
  to       = aws_cloudfront_distribution.site
  id       = each.value
}

import {
  for_each = var.adopt.origin_access_control_id == null ? {} : { this = var.adopt.origin_access_control_id }
  to       = aws_cloudfront_origin_access_control.site
  id       = each.value
}
