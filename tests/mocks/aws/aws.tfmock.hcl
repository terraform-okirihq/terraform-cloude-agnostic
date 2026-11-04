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
