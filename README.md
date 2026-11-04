# terraform-multicloud-foundation

[![ci](https://github.com/terraform-okirihq/terraform-cloude-agnostic/actions/workflows/ci.yml/badge.svg)](https://github.com/terraform-okirihq/terraform-cloude-agnostic/actions/workflows/ci.yml)
[![security](https://github.com/terraform-okirihq/terraform-cloude-agnostic/actions/workflows/security.yml/badge.svg)](https://github.com/terraform-okirihq/terraform-cloude-agnostic/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/terraform-okirihq/terraform-cloude-agnostic/badge)](https://scorecard.dev/viewer/?uri=github.com/terraform-okirihq/terraform-cloude-agnostic)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A production-ready, cloud-agnostic Terraform module that deploys the same
**network, NAT, firewall, servers and object storage** on **AWS, Azure or GCP**
behind one shared interface. It works the same with plain `terraform apply`,
Terraform CLI workspaces, HCP Terraform workspaces and CI/CD pipelines.

| | AWS | Azure | GCP |
|---|---|---|---|
| Network | VPC (DNS on), default security group locked down | Resource group (optional) + VNet | Custom-mode VPC |
| Subnets | Subnets spread across AZs, IGW + route table for public ones | Subnets, default outbound access only on public ones | Regional subnetworks, Private Google Access on private ones |
| NAT (private egress) | NAT gateway + Elastic IP | NAT gateway + static public IP | Cloud Router + Cloud NAT + reserved IP |
| Firewall | Security group: VPC-internal + `ingress_rules` | NSG on every subnet: `ingress_rules` | Firewall rules: internal + `ingress_rules` (by network tag) |
| Servers | EC2 with IMDSv2, encrypted gp3, SSM role, key pair | Linux VM with SSH key only, managed identity, boot diagnostics | Shielded VM, dedicated least-privilege service account |
| Storage | S3 bucket: versioned, SSE, public access blocked | Storage account (TLS 1.2, no public blobs, versioning) + private `data` container | GCS bucket: versioned, uniform access, public access prevention |

Servers default to **Ubuntu 24.04 LTS**. The portable sizes `small`, `medium` and
`large` map to a sensible machine type on each cloud, and any native type such as
`m7i.large`, `Standard_E4s_v5` or `n2-highmem-2` is passed through unchanged:

| size | AWS | Azure | GCP |
|---|---|---|---|
| `small` | t3.small | Standard_B2s | e2-small |
| `medium` | t3.large | Standard_D2s_v5 | e2-standard-2 |
| `large` | m6i.xlarge | Standard_D4s_v5 | n2-standard-4 |

## Choosing an entry point

| Source | Use when | Providers you configure |
|---|---|---|
| `//modules/aws`, `//modules/azure`, `//modules/gcp` | **Recommended.** You deploy to one cloud per configuration. | Only that cloud's provider |
| root module (`cloud = "aws" \| "azure" \| "gcp"`) | The cloud is chosen at runtime (e.g. a CI matrix) by a team that has all three clouds | All of `aws`, `azurerm`, `google` |

All entry points take the same core inputs and return the same outputs, so moving to
another cloud means changing the `source`, the provider block and the cloud-specific inputs.

> Terraform configures every provider a module declares, even ones with no resources.
> That is why the root switch needs all three providers to be configured. The
> per-cloud modules don't have this limitation.

## Usage

### Plain Terraform

```hcl
provider "aws" {
  region = "us-east-1"
}

module "foundation" {
  source  = "<namespace>/foundation/multicloud//modules/aws"
  version = "~> 0.1"

  name        = "acme"
  environment = "dev"
  region      = "us-east-1"
  tags        = { owner = "platform-team" }

  ssh_public_key = file("~/.ssh/id_rsa.pub")

  ingress_rules = [
    { name = "https", from_port = 443, source_cidrs = ["0.0.0.0/0"] },
    { name = "ssh", from_port = 22, source_cidrs = ["203.0.113.0/24"] },
  ]

  servers = {
    web = { subnet = "public", size = "medium", public_ip = true, user_data = file("cloud-init.yaml") }
    api = { size = "large", disk_size_gb = 100 } # private subnet, egress via NAT
  }
}
```

The same call on GCP:

```hcl
module "foundation" {
  source  = "<namespace>/foundation/multicloud//modules/gcp"
  version = "~> 0.1"

  name        = "acme"
  environment = "dev"
  region      = "europe-west1"
  project_id  = "acme-dev-123"
}
```

### Terraform CLI workspaces

Leave out `environment`. The module then uses `terraform.workspace`, so each
workspace gets its own state and its own resource names (`acme-dev-*`, `acme-prod-*`):

```bash
terraform workspace new dev
terraform apply -var-file=env/dev.tfvars
```

See [examples/workspaces](examples/workspaces). It also includes a guard that
blocks applies to the `default` workspace.

### HCP Terraform / Terraform Enterprise

HCP workspace names (such as `foundation-dev`) are usually longer than the
environment name, so set `environment` as a workspace variable. See
[examples/hcp-terraform](examples/hcp-terraform).

### CI/CD

Set `TF_WORKSPACE` to select the workspace and `TF_VAR_environment` to pass the
environment name, then run `init`/`plan`/`apply`. Use OIDC for cloud credentials.
[examples/cicd/deploy.yml](examples/cicd/deploy.yml) is a full GitHub Actions
pipeline: plan on pull requests, apply on `main` with environment approvals.
Create each workspace once with `terraform workspace new <env>` before the pipeline's first run.

## Inputs

### Shared (all entry points)

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Workload name: 3-20 chars, lowercase letters, digits and `-`. |
| `environment` | `string` | `null` | `dev`, `prod`, and so on. When null, `terraform.workspace` is used (after sanitising). |
| `region` | `string` | required | AWS region, Azure location or GCP region. |
| `network_cidr` | `string` | `"10.0.0.0/16"` | IPv4 CIDR for the VPC or VNet. |
| `subnets` | `map(object({ cidr = string, public = optional(bool, false) }))` | `null` | When null, a public `/24` (`.0`) and a private `/24` (`.10`) are derived from `network_cidr`. |
| `create_storage_bucket` | `bool` | `true` | Create the bucket or storage account. |
| `tags` | `map(string)` | `{}` | Merged over `managed-by`, `environment` and `workload`. Converted to valid labels on GCP. |
| `enable_nat_gateway` | `bool` | `true` | Give private subnets outbound internet access through NAT with a static IP. |
| `ingress_rules` | `list(object({ name, protocol = "tcp", from_port, to_port = null, source_cidrs }))` | `[]` | Inbound rules for servers. `protocol` is `tcp` or `udp`. Traffic inside the network is always allowed. |
| `servers` | `map(object({ subnet = "private", size = "small", image = null, disk_size_gb = 30, public_ip = false, user_data = null }))` | `{}` | VMs keyed by name. `user_data` is cloud-init on every cloud. `image`: AMI ID on AWS, `publisher:offer:sku:version` on Azure, image path or family on GCP. |
| `admin_username` | `string` | `"cloudadmin"` | Admin user on servers. Reserved names like `admin` and `root` are rejected. |
| `ssh_public_key` | `string` | `null` | OpenSSH public key for `admin_username`. **Required for servers on Azure.** On AWS you can leave it unset and connect through SSM Session Manager. |

### Cloud-specific

| Module | Name | Default | Description |
|---|---|---|---|
| aws | `availability_zones` | all AZs in the region | AZs that subnets are spread across, round-robin. |
| aws, gcp | `storage_force_destroy` | `false` | Allow destroying a bucket that still holds objects. |
| azure | `resource_group_name` | `null` | Existing resource group to use. When null, `rg-<name>-<env>` is created. |
| azure | `storage_replication_type` | `"LRS"` | `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS` or `RAGZRS`. |
| gcp | `project_id` | required | GCP project. |
| gcp | `storage_class` | `"STANDARD"` | GCS storage class. |

The root module has the shared inputs plus `cloud`, `storage_force_destroy`, and the
objects `aws = { availability_zones }`, `azure = { resource_group_name, storage_replication_type }`
and `gcp = { project_id, storage_class }`.

## Outputs

| Name | Description |
|---|---|
| `network_id` / `network_name` | VPC or VNet ID and name. |
| `subnet_ids` / `subnet_cidrs` | Map of subnet key to ID or CIDR. |
| `storage_bucket_name` | Bucket name (Azure: storage account name). Null when no bucket is created. |
| `storage_bucket_url` | `s3://`, `gs://` or `https://<account>.blob.core.windows.net/data`. |
| `servers` | Map of server key to `{ id, private_ip, public_ip }`. `public_ip` is null for private servers. |
| `nat_public_ip` | Static egress IP of the NAT, for allowlisting. Null when NAT is disabled. |
| `environment`, `name_prefix`, `region`, `tags` | The values the module resolved and applied. |
| `security_group_id` (aws) | Security group attached to servers. |
| `network_security_group_id` (azure) | NSG attached to every subnet. |
| `resource_group_name` (azure) / `azure_resource_group_name` (root) | The Azure resource group used. |

## Operational notes

- **Accessing servers.** On AWS, use SSM Session Manager (`aws ssm start-session`); no
  open port is needed. On Azure and GCP, use SSH. On GCP, if your project enforces
  OS Login, metadata SSH keys are ignored: grant `roles/compute.osAdminLogin` instead.
- **AMI updates.** AWS servers ignore AMI changes after creation, so a new Ubuntu
  release never replaces a running server. Recreate a server deliberately with
  `terraform apply -replace`.
- **NAT cost and availability.** Each cloud gets a single NAT gateway. That's cheaper,
  but zone-redundant only on GCP, where Cloud NAT is regional.
- **GCP IAM.** The deploying identity needs permission to create service accounts and
  grant project IAM roles, because each server gets a log and metric writer service account.
| `cloud` (root only) | The cloud that was selected. |

## Requirements

- Terraform `>= 1.9`
- Providers: `hashicorp/aws >= 6.0`, `hashicorp/azurerm >= 4.20`, `hashicorp/google >= 6.0`, `hashicorp/random >= 3.5`

## Development

```bash
make fmt        # terraform fmt -recursive
make validate   # init + validate the root, every module and every example
make test       # terraform test (mocked providers, no credentials needed)
make lint       # tflint
```

The tests in [tests/](tests) cover each cloud module on its own, with only that cloud's
provider mocked. They also cover the root switch and the shared naming and validation
rules in `modules/context`.

## Publishing to the Terraform Registry

1. Push this code to a **public GitHub repo** named `terraform-<provider>-<name>`,
   for example `terraform-multicloud-foundation`. The registry requires this naming.
2. Sign in to [registry.terraform.io](https://registry.terraform.io) with GitHub and
   choose **Publish → Module**, then pick the repo. For a private registry, publish it
   in HCP Terraform under **Registry → Publish → Module** instead.
3. Run `./scripts/setup-github.sh <owner>/terraform-multicloud-foundation` once to
   apply branch protection and turn on the security features.
4. Releases are automated. [release-please](.github/workflows/release.yml) keeps a
   release PR open; merging it creates the `vX.Y.Z` tag, which the registry
   publishes automatically.
5. Replace `<namespace>` in these docs with your registry namespace (your GitHub
   user or org).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching
model, the Conventional Commit rules and the local checks. Everyone taking part
agrees to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
Every pull request is scanned for secrets (gitleaks), malware (ClamAV) and
Terraform misconfigurations (Trivy, Checkov). Results appear in the repository's
Security tab.

## License

[MIT](LICENSE) © 2026 Gabriel Okiri
