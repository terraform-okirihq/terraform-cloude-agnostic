# CI/CD consumer example

[`deploy.yml`](deploy.yml) is a GitHub Actions pipeline for a repository that
*consumes* this module (copy it to `.github/workflows/` in that repo).

- Pull requests: `fmt`, `validate` and `plan` for every environment.
- Push to `main`: `apply` per environment, gated by GitHub Environments
  (add required reviewers on `prod`).
- The environment is selected with the `TF_WORKSPACE` env var, which Terraform
  uses instead of `terraform workspace select`, and passed to the module via
  `TF_VAR_environment`.
- Cloud auth uses OIDC (no long-lived secrets). Swap the AWS step for
  `azure/login` or `google-github-actions/auth` on other clouds.

The same pattern works in GitLab CI, Azure DevOps or Jenkins: set
`TF_WORKSPACE` + `TF_VAR_environment`, then run `terraform init/plan/apply`.
