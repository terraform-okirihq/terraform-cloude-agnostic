# aws

Single-cloud entry point of the multicloud foundation module. Shares the exact
input/output interface of the other cloud modules - see the
[root README](../../README.md) for inputs, outputs and usage.

```hcl
module "foundation" {
  source  = "<namespace>/foundation/multicloud//modules/aws"
  version = "~> 0.1"
  # ...
}
```
