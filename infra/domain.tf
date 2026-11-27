# Custom domains. Three setups:
#   1. No domain_names                       -> *.cloudfront.net only, nothing here is created.
#   2. domain_names + acm_certificate_arn    -> use that certificate; DNS records only if route53_zone_id is set.
#   3. domain_names + route53_zone_id        -> create + DNS-validate a certificate, and the alias records.

locals {
  create_certificate = length(var.domain_names) > 0 && var.acm_certificate_arn == null && var.route53_zone_id != null
  manage_dns         = length(var.domain_names) > 0 && var.route53_zone_id != null

  certificate_arn = (
    var.acm_certificate_arn != null ? var.acm_certificate_arn :
    local.create_certificate ? aws_acm_certificate_validation.this[0].certificate_arn :
    null
  )

  # Wildcards can't have alias records of their own.
  alias_records = local.manage_dns ? {
    for pair in setproduct([for d in var.domain_names : d if !startswith(d, "*.")], ["A", "AAAA"]) :
    "${pair[0]}/${pair[1]}" => { name = pair[0], type = pair[1] }
  } : {}
}

resource "aws_acm_certificate" "this" {
  count    = local.create_certificate ? 1 : 0
  provider = aws.us_east_1

  domain_name               = var.domain_names[0]
  subject_alternative_names = slice(var.domain_names, 1, length(var.domain_names))
  validation_method         = "DNS"
  tags                      = { Name = local.name }

  lifecycle {
    create_before_destroy = true
  }
}

# Keyed by domain name (known at plan time). "example.com" and "*.example.com"
# share one validation record, hence allow_overwrite.
resource "aws_route53_record" "validation" {
  for_each = local.create_certificate ? toset(var.domain_names) : toset([])

  zone_id         = var.route53_zone_id
  allow_overwrite = true
  ttl             = 300

  name    = one([for o in aws_acm_certificate.this[0].domain_validation_options : o.resource_record_name if o.domain_name == each.key])
  type    = one([for o in aws_acm_certificate.this[0].domain_validation_options : o.resource_record_type if o.domain_name == each.key])
  records = [one([for o in aws_acm_certificate.this[0].domain_validation_options : o.resource_record_value if o.domain_name == each.key])]
}

resource "aws_acm_certificate_validation" "this" {
  count    = local.create_certificate ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# allow_overwrite = false: if a record with this name already exists (e.g. the
# domain points at another site), the apply fails instead of hijacking it.
resource "aws_route53_record" "alias" {
  for_each = local.alias_records

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  allow_overwrite = false

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
