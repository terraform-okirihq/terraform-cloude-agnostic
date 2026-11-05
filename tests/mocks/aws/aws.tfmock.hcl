mock_data "aws_availability_zones" {
  defaults = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

mock_data "aws_partition" {
  defaults = {
    partition = "aws"
  }
}

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_data "aws_ami" {
  defaults = {
    id = "ami-0123456789abcdef0"
  }
}

mock_resource "aws_eip" {
  defaults = {
    public_ip = "203.0.113.10"
  }
}

mock_resource "aws_instance" {
  defaults = {
    private_ip = "10.0.10.5"
    public_ip  = "203.0.113.20"
  }
}

# AWS validates ARN formats, so resources referenced by ARN need real-looking ones.
mock_resource "aws_cloudwatch_log_group" {
  defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock" }
}

mock_resource "aws_iam_role" {
  defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
}

mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
}

mock_resource "aws_sns_topic" {
  defaults = { arn = "arn:aws:sns:us-east-1:123456789012:mock" }
}

mock_resource "aws_lb" {
  defaults = {
    arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/0123456789abcdef"
    dns_name = "mock-123.us-east-1.elb.amazonaws.com"
  }
}

mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/0123456789abcdef" }
}

mock_resource "aws_ecs_cluster" {
  defaults = {
    arn = "arn:aws:ecs:us-east-1:123456789012:cluster/mock"
    id  = "arn:aws:ecs:us-east-1:123456789012:cluster/mock"
  }
}

mock_resource "aws_ecs_task_definition" {
  defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/mock:1" }
}

mock_resource "aws_eks_cluster" {
  defaults = {
    arn      = "arn:aws:eks:us-east-1:123456789012:cluster/mock"
    endpoint = "https://MOCK.gr7.us-east-1.eks.amazonaws.com"
    version  = "1.34"
  }
}

mock_resource "aws_lambda_function" {
  defaults = { arn = "arn:aws:lambda:us-east-1:123456789012:function:mock" }
}

mock_resource "aws_lambda_function_url" {
  defaults = { function_url = "https://mock.lambda-url.us-east-1.on.aws/" }
}

mock_resource "aws_db_instance" {
  defaults = {
    address = "mock.abc123.us-east-1.rds.amazonaws.com"
    master_user_secret = [{
      secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-mock"
    }]
  }
}

mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012" }
}

mock_data "aws_elb_service_account" {
  defaults = { arn = "arn:aws:iam::127311923021:root" }
}

mock_resource "aws_s3_bucket" {
  defaults = { arn = "arn:aws:s3:::mock-bucket" }
}

mock_resource "aws_wafv2_web_acl" {
  defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/mock/00000000-0000-0000-0000-000000000000" }
}
