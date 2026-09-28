mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name              = "hg-test"
  vpc_id            = "vpc-0123456789abcdef0"
  vpc_cidr          = "10.60.0.0/16"
  alb_subnet_ids    = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]
  app_subnet_ids    = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]
  alb_ingress_cidrs = ["10.40.0.0/16", "10.60.0.0/16"]
  s3_prefix_list_id = "pl-63a5400a"
  carrier_api_cidrs = ["203.0.113.200/32"]
  access_logs       = { bucket = "harbor-log-archive-444455556666-us-east-1", prefix = "hg-test/alb" }
  certificate_arn   = "arn:aws:acm:us-east-1:111122223333:certificate/11111111-2222-3333-4444-555555555555"
  kms_key_arn       = "arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555"

  services = {
    web = {
      image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-web@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      cpu               = 1024
      memory            = 3072
      desired_count     = 2
      container_port    = 8080
      health_check_path = "/healthz"
      host_name         = "warehouse.example.com"
    }
    api = {
      image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-api@sha256:2222222222222222222222222222222222222222222222222222222222222222"
      cpu               = 2048
      memory            = 6144
      desired_count     = 2
      container_port    = 8080
      health_check_path = "/actuator/health"
      host_name         = "api.example.com"
      secrets           = { DB_CREDENTIALS = "arn:aws:secretsmanager:us-east-1:111122223333:secret:harbor-app-AbCdEf" }
    }
  }
}

run "load_balancer_is_internal" {
  command = apply

  assert {
    condition     = aws_lb.this.internal && toset(aws_lb.this.subnets) == toset(var.alb_subnet_ids)
    error_message = "The load balancer must be internal and sit in the private subnets it is given."
  }

  assert {
    condition     = alltrue([for r in concat(values(aws_vpc_security_group_ingress_rule.alb_https), values(aws_vpc_security_group_ingress_rule.alb_http)) : !contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_ipv4, r.cidr_ipv6, "none"))])
    error_message = "No load balancer ingress rule may admit 0.0.0.0/0 or ::/0."
  }

  assert {
    condition     = toset(output.network_exposure.ingress_cidrs) == toset(var.alb_ingress_cidrs)
    error_message = "HTTP and HTTPS must admit exactly the listed private client ranges."
  }
}

run "tasks_reach_aws_apis_privately" {
  command = apply

  assert {
    condition     = length(setintersection(output.network_exposure.egress_cidrs, ["0.0.0.0/0", "::/0"])) == 0
    error_message = "No task egress rule may reach 0.0.0.0/0 or ::/0."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.services_https_vpc.cidr_ipv4 == var.vpc_cidr && aws_vpc_security_group_egress_rule.services_https_s3.prefix_list_id == "pl-63a5400a"
    error_message = "HTTPS to AWS APIs must go to the VPC (interface endpoints) and to S3 through the gateway endpoint prefix list."
  }

  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.services_https_carrier) == ["203.0.113.200/32"]
    error_message = "The only destination outside the VPC is the parcel carrier's published address."
  }
}

run "access_logs_go_to_the_log_archive" {
  command = apply

  assert {
    condition     = one(aws_lb.this.access_logs).enabled && one(aws_lb.this.access_logs).bucket == "harbor-log-archive-444455556666-us-east-1" && one(aws_lb.this.access_logs).prefix == "hg-test/alb"
    error_message = "Access logs must be on and delivered to the central log archive bucket."
  }
}

run "rejects_public_client_ranges" {
  command = plan

  variables {
    alb_ingress_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.alb_ingress_cidrs]
}

run "rejects_non_rfc1918_client_ranges" {
  command = plan

  variables {
    alb_ingress_cidrs = ["10.40.0.0/16", "203.0.113.0/24"]
  }

  expect_failures = [var.alb_ingress_cidrs]
}

run "rejects_wide_carrier_ranges" {
  command = plan

  variables {
    carrier_api_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.carrier_api_cidrs]
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
    condition     = one(one(aws_lb_listener_rule.host["web"].condition).host_header).values == toset(["warehouse.example.com"])
    error_message = "warehouse.example.com must route to the web target group."
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
    condition     = jsondecode(aws_iam_role_policy.execution_secrets[0].policy).Statement[0].Resource == ["arn:aws:secretsmanager:us-east-1:111122223333:secret:harbor-app-AbCdEf"]
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
        host_name         = "warehouse.example.com"
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
        host_name         = "warehouse.example.com"
      }
    }
  }

  expect_failures = [var.services]
}
