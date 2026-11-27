#!/usr/bin/env bash
# One-time AWS account setup for Nuxt deploys. Run it with admin credentials
# for the target account (e.g. `aws sso login` / AWS_PROFILE=...).
#
#   infra/bootstrap/bootstrap.sh <github-owner> [region] [repository-pattern]
#
#   github-owner        GitHub org or user, e.g. my-org
#   region              default: your AWS CLI region, else us-east-1
#   repository-pattern  which repos may deploy: "*" (default), "web-*", "shop"
#
# Creates (or updates) the CloudFormation stack "nuxt-github-deploy":
#   - GitHub OIDC provider (skipped if the account already has one)
#   - Terraform state bucket   nuxt-tfstate-<account>-<region>
#   - Deploy role              nuxt-github-deploy
#
# Safe to re-run: an existing stack is updated, nothing is duplicated.
# Optional env: RESOURCE_PREFIX (default nuxt), ALLOW_DESTROY (default false).
set -euo pipefail

[[ $# -ge 1 ]] || { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

owner="$1"
region="${2:-$(aws configure get region 2>/dev/null || true)}"
region="${region:-us-east-1}"
pattern="${3:-*}"
prefix="${RESOURCE_PREFIX:-nuxt}"
allow_destroy="${ALLOW_DESTROY:-false}"
stack="${prefix}-github-deploy"
template="$(dirname "$0")/aws-account.cfn.yml"

account="$(aws sts get-caller-identity --query Account --output text)"
echo "AWS account $account, region $region, stack $stack"

params=(
  "GitHubOwner=$owner"
  "RepositoryPattern=$pattern"
  "ResourcePrefix=$prefix"
  "AllowDestroy=$allow_destroy"
)

# The OIDC provider decision is made once, when the stack is first created.
# On updates, CloudFormation keeps the previous value.
if ! aws cloudformation describe-stacks --stack-name "$stack" --region "$region" >/dev/null 2>&1; then
  if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text \
      | tr '\t' '\n' | grep -q '/token.actions.githubusercontent.com$'; then
    echo "GitHub OIDC provider already exists: reusing it."
    params+=("CreateOIDCProvider=false")
  else
    echo "No GitHub OIDC provider yet: creating it."
    params+=("CreateOIDCProvider=true")
  fi
fi

aws cloudformation deploy \
  --region "$region" \
  --stack-name "$stack" \
  --template-file "$template" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${params[@]}"

cat <<EOF

Done. Set these GitHub Actions variables on each repository
(Settings > Secrets and variables > Actions > Variables). For a GitHub
organization you can set them once at the org level instead:

  AWS_ACCOUNT_ID = $account
  AWS_REGION     = $region
EOF
if [[ "$prefix" != "nuxt" ]]; then
  echo "  RESOURCE_PREFIX = $prefix"
fi
echo
echo "Every Nuxt repo that contains infra/ and .github/workflows/deploy.yml now deploys on push."
