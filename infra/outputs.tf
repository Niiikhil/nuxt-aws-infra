# The pipeline reads bucket_name, distribution_id and site_url.

output "bucket_name" {
  value = aws_s3_bucket.site.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "distribution_domain_name" {
  description = "Point DNS here (CNAME) when DNS is not in Route 53."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  value = "https://${length(var.domain_names) > 0 ? var.domain_names[0] : aws_cloudfront_distribution.site.domain_name}"
}

output "certificate_arn" {
  value = local.certificate_arn
}
