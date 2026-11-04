#!/usr/bin/env bash
# One-time GitHub repository hardening. Run after creating and pushing the repo:
#
#   ./scripts/setup-github.sh <owner>/<repo>
#
# Requires the GitHub CLI (`gh auth login`) with admin rights on the repo.
set -euo pipefail

repo="${1:?usage: $0 <owner>/<repo>}"

echo "==> Repository settings: squash-merge only, PR title as commit, auto-delete branches"
gh api -X PATCH "repos/${repo}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F allow_auto_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F has_wiki=false >/dev/null

echo "==> Security: secret scanning + push protection"
gh api -X PATCH "repos/${repo}" --input - >/dev/null <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
JSON

echo "==> Security: Dependabot alerts + security updates, private vulnerability reporting"
gh api -X PUT "repos/${repo}/vulnerability-alerts" >/dev/null
gh api -X PUT "repos/${repo}/automated-security-fixes" >/dev/null
gh api -X PUT "repos/${repo}/private-vulnerability-reporting" >/dev/null

echo "==> Actions: read-only default token, allow release-please to open PRs"
gh api -X PUT "repos/${repo}/actions/permissions/workflow" \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true >/dev/null

echo "==> Branch protection ruleset for the default branch"
existing=$(gh api "repos/${repo}/rulesets" --jq '.[] | select(.name=="protect-main") | .id')
if [[ -n "${existing}" ]]; then
  gh api -X PUT "repos/${repo}/rulesets/${existing}" --input .github/rulesets/main.json >/dev/null
else
  gh api -X POST "repos/${repo}/rulesets" --input .github/rulesets/main.json >/dev/null
fi

echo "==> Topics (helps people find the module)"
gh api -X PUT "repos/${repo}/topics" \
  -f "names[]=terraform" -f "names[]=terraform-module" -f "names[]=multicloud" \
  -f "names[]=aws" -f "names[]=azure" -f "names[]=gcp" -f "names[]=infrastructure-as-code" >/dev/null

echo "Done. Review: https://github.com/${repo}/settings"
