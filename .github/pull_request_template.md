## What does this PR change?

<!-- Short description. The PR title must follow Conventional Commits,
     e.g. "feat(azure): add zone support for servers" or "fix(gcp): ...". -->

## Which clouds are affected?

- [ ] AWS
- [ ] Azure
- [ ] GCP
- [ ] Shared (`modules/context`, root switch, CI, docs)

## Checklist

- [ ] `make fmt validate test` passes locally
- [ ] Tests added/updated in `tests/` for new behaviour
- [ ] The shared interface stays identical across `modules/aws`, `modules/azure` and `modules/gcp`
- [ ] README updated for new or changed inputs/outputs
- [ ] Breaking change? Title uses `feat!:` / `fix!:` and the description explains the migration
