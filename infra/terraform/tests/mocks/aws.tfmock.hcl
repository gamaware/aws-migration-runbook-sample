# Shared mock data for every `terraform test` in this repository. The mock provider invents random strings for
# computed attributes; the AWS provider rejects those where it expects an ARN or an ID with a prefix. These
# defaults use AWS documentation example values so the mocked apply passes the provider's own validation.

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::111122223333:role/mock-role"
  }
}

mock_resource "aws_cloudwatch_log_group" {
  defaults = {
    arn = "arn:aws:logs:us-east-1:111122223333:log-group:mock"
  }
}

mock_resource "aws_lb" {
  defaults = {
    arn        = "arn:aws:elasticloadbalancing:us-east-1:111122223333:loadbalancer/app/mock/1234567890abcdef"
    arn_suffix = "app/mock/1234567890abcdef"
    dns_name   = "internal-mock-1234567890.us-east-1.elb.amazonaws.com"
    zone_id    = "Z35SXDOTRQ7X7K"
  }
}

mock_resource "aws_lb_target_group" {
  defaults = {
    arn = "arn:aws:elasticloadbalancing:us-east-1:111122223333:targetgroup/mock/1234567890abcdef"
  }
}

mock_resource "aws_lb_listener" {
  defaults = {
    arn = "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/mock/1234567890abcdef/1234567890abcdef"
  }
}

mock_resource "aws_ecs_cluster" {
  defaults = {
    arn = "arn:aws:ecs:us-east-1:111122223333:cluster/mock"
    id  = "arn:aws:ecs:us-east-1:111122223333:cluster/mock"
  }
}

mock_resource "aws_ecs_task_definition" {
  defaults = {
    arn = "arn:aws:ecs:us-east-1:111122223333:task-definition/mock:1"
  }
}

mock_resource "aws_kms_key" {
  defaults = {
    arn    = "arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555"
    key_id = "11111111-2222-3333-4444-555555555555"
  }
}

mock_resource "aws_secretsmanager_secret" {
  defaults = {
    arn = "arn:aws:secretsmanager:us-east-1:111122223333:secret:mock-AbCdEf"
  }
}

mock_resource "aws_db_instance" {
  defaults = {
    arn     = "arn:aws:rds:us-east-1:111122223333:db:mock"
    address = "mock.abcdefghijkl.us-east-1.rds.amazonaws.com"
    port    = 5432
    master_user_secret = [{
      kms_key_id    = "arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555"
      secret_arn    = "arn:aws:secretsmanager:us-east-1:111122223333:secret:rds-mock-AbCdEf"
      secret_status = "active"
    }]
  }
}

mock_resource "aws_dms_replication_instance" {
  defaults = {
    replication_instance_arn = "arn:aws:dms:us-east-1:111122223333:rep:MOCKINSTANCE"
  }
}

mock_resource "aws_dms_endpoint" {
  defaults = {
    endpoint_arn = "arn:aws:dms:us-east-1:111122223333:endpoint:MOCKENDPOINT"
  }
}

mock_resource "aws_dms_replication_task" {
  defaults = {
    replication_task_arn = "arn:aws:dms:us-east-1:111122223333:task:MOCKTASK"
  }
}

mock_resource "aws_acm_certificate" {
  defaults = {
    arn = "arn:aws:acm:us-east-1:111122223333:certificate/11111111-2222-3333-4444-555555555555"
  }
}

mock_data "aws_region" {
  defaults = {
    region = "us-east-1"
    name   = "us-east-1"
  }
}

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "111122223333"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}
