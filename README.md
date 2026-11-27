# nuxt-aws-infra

Drop-in AWS hosting and deployment for any static Nuxt site (`nuxi generate`). Copy two folders into a Nuxt repo, push, and it's live on S3 + CloudFront. Each project is self-contained; nothing depends on this repo afterwards.

## Once per AWS account (admin, about 2 minutes)

GitHub can't reach AWS until AWS trusts it, so an admin does this once per account:

```bash
# with admin credentials for the account (aws sso login, AWS_PROFILE=…)
infra/bootstrap/bootstrap.sh my-github-org us-east-1
```

This creates a CloudFormation stack `nuxt-github-deploy` with:
- **GitHub OIDC provider**, so GitHub can sign in without stored AWS keys. Reused if the account already has one.
- **State bucket** `nuxt-tfstate-<account>-<region>`, where Terraform tracks what it created.
- **Deploy role** `nuxt-github-deploy`. Only deploy jobs from `my-github-org`'s repos can use it. By default it may manage S3 buckets and CloudFront functions of any name, so each environment can choose its own names. To restrict it, run with `NAME_PATTERN="mysite-*"`. Deleting buckets and distributions is always denied.

Re-running it is safe; the stack is updated in place. To limit which repos can deploy, pass a third argument (`"web-*"`, or one repo name).

Then set two **organization variables** (Settings → Secrets and variables → Actions → Variables), with the values the script prints:

```
AWS_ACCOUNT_ID = 111111111111
AWS_REGION     = us-east-1
```

For a personal GitHub account (or a plan without organization variables for private repos), set them on each repo instead.

> **New AWS accounts:** AWS may refuse to create CloudFront distributions until the account is verified (`AccessDenied: Your account must be verified before you can add new CloudFront resources`). Open a case at [AWS Support](https://console.aws.amazon.com/support/home#/) → *Account and billing*, paste that error, and re-run the deploy once AWS confirms. Basic support handles this for free.

## For every new Nuxt project

**New repo:** click **Use this template** on GitHub, then add your Nuxt app to it.

**Existing Nuxt repo:** copy the two folders in:

```bash
cp -R nuxt-aws-infra/infra nuxt-aws-infra/.github  my-nuxt-app/
cd my-nuxt-app && git add infra .github && git commit -m "Add AWS deploy" && git push
```

Push to `develop` → dev, `staging` → staging, `main` → production. The first deploy creates the infrastructure (about 5–10 minutes, mostly CloudFront rolling out). Later deploys just build and upload. The site URL appears in the run summary and on the repo's Environments page.

Optional per-project settings (custom domain, SPA mode, redirects, build env) are GitHub variables, listed in [infra/README.md](infra/README.md).

## What's here

```
infra/
  bootstrap/
    bootstrap.sh            once per AWS account
    aws-account.cfn.yml     OIDC provider, state bucket, deploy role
  main.tf                   S3 bucket, CloudFront, function, bucket policy
  domain.tf                 optional certificate + Route 53 records
  edge-function.js.tftpl    redirects and /about → /about/index.html
  variables.tf, outputs.tf, providers.tf, versions.tf
  imports.tf                take over resources made by hand
  tests/                    terraform test (mocked AWS, no credentials)
.github/
  workflows/deploy.yml      PR checks; build → plan → safety check → apply → upload → invalidate
  actions/nuxt-build/       install + nuxi generate (npm, pnpm or yarn)
```

## Security notes

- No AWS keys are stored anywhere. Each job gets temporary credentials through GitHub OIDC.
- Only jobs running in a GitHub *environment* (the deploy job) can assume the role. Pull requests can't.
- The role can't touch IAM, and it can't delete buckets or distributions. With the default `NAME_PATTERN="*"` it can modify any S3 bucket and CloudFront resource in the account. Keep this account for your sites, or restrict it with `NAME_PATTERN`. CloudFront distributions and certificates can never be limited by name.
- Add reviewers to each repo's `production` environment to require approval for production deploys.
