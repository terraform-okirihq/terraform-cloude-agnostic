# Contributing

Thanks for helping improve this module. This guide covers local setup, the
branching model, commit conventions and how releases happen.

## Local setup

Requirements: Terraform >= 1.9, [tflint](https://github.com/terraform-linters/tflint)
and optionally [pre-commit](https://pre-commit.com).

```bash
pre-commit install          # run fmt/validate/lint/secret checks on every commit
make fmt validate test lint # same checks CI runs
```

Tests use mocked providers, so **no cloud credentials are needed**.

## Branching model

The project uses **trunk-based development** (GitHub Flow): `main` is always
releasable, and all work happens on short-lived branches merged by pull request.

```
main  ──●─────────●───────────●──────────●──  (protected; tags vX.Y.Z)
         \       /             \        /
          feat/azure-zones      fix/gcp-nat-logging
```

| Branch | Purpose | Example |
|---|---|---|
| `main` | Protected trunk. No direct pushes. | |
| `feat/<topic>` | New functionality | `feat/aws-multi-nat` |
| `fix/<topic>` | Bug fixes | `fix/azure-nsg-priority` |
| `docs/<topic>` | Documentation only | `docs/workspaces-guide` |
| `ci/<topic>`, `chore/<topic>` | Tooling, CI, dependencies | `ci/add-trivy` |
| `release-please--*` | Created automatically by the release bot | |

Rules on `main`, enforced by [.github/rulesets/main.json](.github/rulesets/main.json):

- Pull request required, with 1 approving review from a code owner
- Required checks: `ci-ok`, `secret-scan (gitleaks)`, `malware-scan (clamav)`, `pr-title`
- Branch must be up to date with `main`, and all review threads resolved
- Linear history (squash merge only), no force pushes, no deletion

## Commit and PR titles

PRs are squash-merged, and the **PR title becomes the commit message**. Titles
must follow [Conventional Commits](https://www.conventionalcommits.org/):

| Title | Release effect |
|---|---|
| `fix(aws): correct NAT route` | patch: 0.1.0 → 0.1.1 |
| `feat(gcp): add zonal server placement` | minor: 0.1.0 → 0.2.0 |
| `feat!: rename storage outputs` | breaking: minor while `0.x`, major from 1.0 |
| `docs:`, `test:`, `ci:`, `chore:`, `refactor:` | no release |

Use the scopes `aws`, `azure`, `gcp`, `context`, `root`, `examples` or `ci`.

## Releases

Releases are fully automated with [release-please](https://github.com/googleapis/release-please):

1. Merged PRs accumulate in an open **release PR** that bumps the version and updates `CHANGELOG.md`.
2. A maintainer merges the release PR when it's time to ship.
3. That creates the `vX.Y.Z` tag and GitHub Release, and the Terraform Registry publishes the new version automatically.

## Design rules

- `modules/aws`, `modules/azure` and `modules/gcp` must keep an **identical shared
  interface**. Add a shared input to all three and to `modules/context`.
- Put validation and naming logic in `modules/context` so it's defined once.
- Secure defaults: encryption on, public access off, least privilege.
- Every new behaviour needs a test in `tests/`.
