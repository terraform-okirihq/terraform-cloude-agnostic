# Security Policy

## Supported versions

Only the latest minor release receives security fixes.

| Version | Supported |
|---|---|
| latest `0.x` | ✅ |
| older | ❌ |

## Reporting a vulnerability

**Do not open a public issue.** Report it privately through
[GitHub private vulnerability reporting](https://github.com/terraform-okirihq/terraform-cloude-agnostic/security/advisories/new).

Please include the affected version, the cloud, a minimal configuration and the
impact. You can expect an acknowledgement within 5 working days and a fix or
mitigation plan within 30 days for confirmed issues.

## Accepted scanner findings

Trivy and Checkov scan every pull request. Findings that reflect deliberate
design decisions are recorded, with the reason for each, in:

- [.checkov.yaml](.checkov.yaml) for module-wide decisions, plus inline
  `#checkov:skip=<ID>:<reason>` comments on specific resources
- [.trivyignore.yaml](.trivyignore.yaml)

Changing one of these entries needs a reviewed pull request, like any other change.

## How this repository is protected

- **Secret scanning**: gitleaks scans the full git history on every PR, and GitHub push protection blocks secrets before they land.
- **Malware scanning**: ClamAV scans the repository on every PR and weekly.
- **Code scanning**: Trivy and Checkov scan the Terraform for misconfigurations; results appear in the Security tab.
- **Supply chain**: Dependabot updates actions and providers, dependency review blocks high-severity dependency changes, and OpenSSF Scorecard tracks repository hygiene.
- **Branch protection**: `main` only changes through reviewed pull requests with passing checks.
