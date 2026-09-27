mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name              = "hg-test"
  vpc_id            = "vpc-0123456789abcdef0"
  vpc_cidr          = "10.60.0.0/16"
  public_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  app_subnet_ids    = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  kms_key_arn       = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"

  services = {
    web = {
      image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-web@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      cpu               = 1024
      memory            = 3072
      desired_count     = 2
      container_port    = 8080
      health_check_path = "/healthz"
      host_name         = "shop.example.com"
    }
    api = {
      image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-api@sha256:2222222222222222222222222222222222222222222222222222222222222222"
      cpu               = 2048
      memory            = 6144
      desired_count     = 2
      container_port    = 8080
      health_check_path = "/actuator/health"
      host_name         = "api.example.com"
      secrets           = { DB_CREDENTIALS = "arn:aws:secretsmanager:us-east-1:123456789012:secret:harbor-app-AbCdEf" }
    }
  }
}

run "http_only_redirects_to_https" {
  command = apply

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "Port 80 must only redirect to HTTPS."
  }

  assert {
    condition     = startswith(aws_lb_listener.https.ssl_policy, "ELBSecurityPolicy-TLS13")
    error_message = "The HTTPS listener must use a TLS 1.3 policy."
  }
}

run "hosts_route_to_their_service" {
  command = apply

  assert {
    condition     = one(one(aws_lb_listener_rule.host["api"].condition).host_header).values == toset(["api.example.com"])
    error_message = "api.example.com must route to the api target group."
  }

  assert {
    condition     = one(one(aws_lb_listener_rule.host["web"].condition).host_header).values == toset(["shop.example.com"])
    error_message = "shop.example.com must route to the web target group."
  }
}

run "tasks_are_private_and_hardened" {
  command = apply

  assert {
    condition     = alltrue([for s in aws_ecs_service.this : !one(s.network_configuration).assign_public_ip])
    error_message = "Tasks must not get public IPs."
  }

  assert {
    condition     = alltrue([for t in aws_ecs_task_definition.this : jsondecode(t.container_definitions)[0].readonlyRootFilesystem && jsondecode(t.container_definitions)[0].user != "0"])
    error_message = "Containers must run as a non-root user on a read-only root file system."
  }

  assert {
    condition     = alltrue([for s in aws_ecs_service.this : one(s.deployment_circuit_breaker).rollback])
    error_message = "A failed deployment must roll back on its own."
  }
}

run "task_size_follows_the_plan" {
  command = apply

  assert {
    condition     = aws_ecs_task_definition.this["api"].cpu == "2048" && aws_ecs_task_definition.this["api"].memory == "6144"
    error_message = "Task size must come from plan/target.yaml through var.services."
  }
}

run "one_rule_per_shared_port" {
  command = apply

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.services_from_alb) == 1
    error_message = "Two services on port 8080 must produce one ingress rule, not a duplicate."
  }
}

run "execution_role_reads_only_listed_secrets" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role_policy.execution_secrets[0].policy).Statement[0].Resource == ["arn:aws:secretsmanager:us-east-1:123456789012:secret:harbor-app-AbCdEf"]
    error_message = "The execution role may read only the secrets the services reference."
  }
}

run "rejects_image_tags" {
  command = plan

  variables {
    services = {
      web = {
        image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-web:latest"
        cpu               = 1024
        memory            = 3072
        desired_count     = 2
        container_port    = 8080
        health_check_path = "/healthz"
        host_name         = "shop.example.com"
      }
    }
  }

  expect_failures = [var.services]
}

run "rejects_single_task_services" {
  command = plan

  variables {
    services = {
      web = {
        image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-web@sha256:1111111111111111111111111111111111111111111111111111111111111111"
        cpu               = 1024
        memory            = 3072
        desired_count     = 1
        container_port    = 8080
        health_check_path = "/healthz"
        host_name         = "shop.example.com"
      }
    }
  }

  expect_failures = [var.services]
}
