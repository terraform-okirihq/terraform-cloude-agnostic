# This output contract is shared by every cloud submodule; keep them in sync.

output "network_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "network_name" {
  description = "VPC Name tag."
  value       = "${local.name_prefix}-vpc"
}

output "subnet_ids" {
  description = "Map of subnet key => subnet ID."
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "subnet_cidrs" {
  description = "Map of subnet key => CIDR."
  value       = { for k, s in aws_subnet.this : k => s.cidr_block }
}

output "storage_bucket_name" {
  description = "S3 bucket name."
  value       = one(aws_s3_bucket.this[*].bucket)
}

output "storage_bucket_url" {
  description = "s3:// URL of the bucket."
  value       = var.create_storage_bucket ? "s3://${aws_s3_bucket.this[0].bucket}" : null
}

output "environment" {
  description = "Resolved environment name."
  value       = module.context.environment
}

output "name_prefix" {
  description = "Prefix applied to all resource names."
  value       = local.name_prefix
}

output "region" {
  description = "Region the resources were deployed to."
  value       = var.region
}

output "tags" {
  description = "Effective tags."
  value       = local.tags
}

output "servers" {
  description = "Map of server key => { id, private_ip, public_ip }."
  value = {
    for k, i in aws_instance.server : k => {
      id         = i.id
      private_ip = i.private_ip
      public_ip  = local.servers[k].public_ip ? i.public_ip : null
    }
  }
}

output "nat_public_ip" {
  description = "Static egress IP of the NAT gateway (null when NAT is disabled)."
  value       = one(aws_eip.nat[*].public_ip)
}

# AWS-specific extra outputs.
output "security_group_id" {
  description = "Security group attached to servers."
  value       = aws_security_group.servers.id
}
