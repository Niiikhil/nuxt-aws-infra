# infra

AWS hosting for this Nuxt site, created and deployed by `.github/workflows/deploy.yml`. Pushing to a deploy branch builds the site, creates or updates the infrastructure, and publishes it.

```
visitor ─► CloudFront ─► CloudFront Function ─► private S3 bucket
           HTTPS, HTTP/3,   301 redirects,         versioned, encrypted,
           security headers /about → /about/index.html  readable only by CloudFront
```

## What gets created (per environment)

| Resource | Name |
|---|---|
| S3 bucket (private, encrypted, versioned, old files kept 30 days) | `nuxt-<project>-<env>-<account id>` |
| Bucket policy (only this distribution can read; HTTPS only) | |
| CloudFront Origin Access Control | `nuxt-<project>-<env>-oac` |
| CloudFront Function (redirects, `index.html` rewrites) | `nuxt-<project>-<env>-viewer-request` |
| CloudFront distribution | |
| ACM certificate + Route 53 records, *only with a custom domain in Route 53* | |

`<project>` is the GitHub variable `PROJECT_NAME`, or else the repository name. Terraform state is stored at `<project>/<env>/terraform.tfstate` in the account's state bucket. That state is how re-running the pipeline updates resources instead of creating them again.

## Branches and environments

| Event | Result |
|---|---|
| Pull request | Builds the site and checks the Terraform. No AWS access |
| Push to `develop` | Deploys **dev** |
| Push to `staging` | Deploys **staging** |
| Push to `main` | Deploys **production** |
| Actions → deploy → Run workflow | Deploys the environment you pick |

GitHub creates each environment the first time it's deployed. To require approval before production deploys, add reviewers under Settings → Environments → production.

To change which branch deploys where, edit the `case` in the `resolve` job of `deploy.yml`, and the `branches:` list at the top.

## GitHub variables

**Required.** Set these once at the organization level and every repo uses them. They come from the bootstrap script.

| Variable | Example |
|---|---|
| `AWS_ACCOUNT_ID` | `111111111111` |
| `AWS_REGION` | `us-east-1` |

**Optional, per repository or per environment.** Environment-level values override repository-level ones, and those override organization-level ones.

| Variable | Example | Effect |
|---|---|---|
| `PROJECT_NAME` | `shop` | Resource and state names (default: the repo name) |
| `DOMAIN_NAMES` | `example.com,www.example.com` | Custom domains |
| `ROUTE53_ZONE_ID` | `Z0123456789ABC` | With `DOMAIN_NAMES`: certificate and DNS records are created for you |
| `ACM_CERTIFICATE_ARN` | `arn:aws:acm:us-east-1:…` | With `DOMAIN_NAMES`, when DNS is elsewhere. Then CNAME the domain to the `distribution_domain_name` output shown in the deploy log |
| `SPA_MODE` | `true` | For `ssr: false` apps |
| `REDIRECTS` | `{"/old":"/new"}` | 301 redirects. The query string is dropped |
| `PRICE_CLASS` | `PriceClass_All` | Edge locations (default: North America and Europe) |
| `WEB_ACL_ID` | `arn:aws:wafv2:us-east-1:…` | Attach a WAF |
| `NODE_VERSION` | `22` | Default: `.nvmrc` / `.node-version`, else 22 |
| `BUILD_COMMAND` | `pnpm run generate` | Default: the `generate` script, else `npx nuxi generate` |
| `NUXT_*` (variables or secrets) | `NUXT_PUBLIC_API_BASE` | Passed to the build |
| `TF_VAR_*` | `TF_VAR_noncurrent_version_expiration_days=90` | Any other Terraform input |

Typical setup: on the `production` environment, set `DOMAIN_NAMES=example.com,www.example.com` and `ROUTE53_ZONE_ID=Z…`. Leave dev without a domain, and it gets a `*.cloudfront.net` URL.

Settings can also go in `infra/env/<env>.tfvars` if you prefer them in code review. A tfvars file wins over GitHub variables.

## Safety checks

Before applying, every deploy checks the plan:
- **Deleting or replacing** infrastructure is blocked. If you really mean it, set `ALLOW_DESTROY=true` on that environment for one run, then remove it.
- **A second bucket or distribution** in an environment that already exists is blocked. This usually means `PROJECT_NAME` or the repo name changed. Set `ALLOW_NEW_SITE_RESOURCES=true` for one run if intended.

The bucket and distribution also have Terraform `prevent_destroy`, and the deploy role is denied deleting them unless the bootstrap ran with `ALLOW_DESTROY=true`.

## Taking over a site that already exists

For a site that was created by hand, set these on its environment:
```
TF_VAR_bucket_name = nuxt-old-bucket
TF_VAR_adopt       = {"bucket_name":"nuxt-old-bucket","distribution_id":"E1234567890ABC"}
```
The deploy imports them instead of creating new ones. Read the plan in the run summary for what else changes. The bucket name must start with `nuxt-`, because the deploy role can only manage those buckets.

## Testing locally

```bash
cd infra
terraform init -backend=false && terraform validate && terraform test   # no AWS needed
```

## Removing an environment

Deletion is deliberately blocked. To remove one:
1. Empty the bucket.
2. Disable, then delete, the distribution in the AWS console.
3. Delete the bucket.
4. Delete `<project>/<env>/terraform.tfstate` from the state bucket.
