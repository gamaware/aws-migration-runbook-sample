data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  secret_arns = distinct(flatten([for s in values(var.services) : values(s.secrets)]))
  # Counted by secret names, which are known at plan time even when the ARNs are not.
  has_secrets = length(flatten([for s in values(var.services) : keys(s.secrets)])) > 0

  # Services may share a port; security group rules must not repeat, so they are keyed by port.
  container_ports = toset([for s in values(var.services) : tostring(s.container_port)])
}

# --- Load balancer ---------------------------------------------------------------------------------------------

# Internal: warehouse staff reach it from the corporate network over the Site-to-Site VPN, the storefront from its
# peered VPC, and the web tasks from inside the VPC. Nothing on the internet can reach it.
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internal load balancer for the warehouse web app and the inventory API"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Port 80 only answers with a redirect to HTTPS (aws_lb_listener.http); no content is served.
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value}, redirected to HTTPS"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_services" {
  for_each = local.container_ports

  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to the ECS tasks on port ${each.value}"
  referenced_security_group_id = aws_security_group.services.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}

# Access logs go to the central log archive bucket (var.access_logs), which carries the Elastic Load Balancing
# log-delivery policy. ALB access logging supports only SSE-S3, so the workload does not own that bucket.
resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = true
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.alb_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = var.access_logs.bucket
    prefix  = var.access_logs.prefix
    enabled = true
  }
}

resource "aws_lb_target_group" "this" {
  for_each = var.services

  name                 = "${var.name}-${each.key}"
  port                 = each.value.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[var.default_service].arn
  }
}

resource "aws_lb_listener_rule" "host" {
  for_each = var.services

  listener_arn = aws_lb_listener.https.arn
  priority     = 100 + index(sort(keys(var.services)), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.host_name]
    }
  }
}

# --- ECS services ----------------------------------------------------------------------------------------------

resource "aws_security_group" "services" {
  name        = "${var.name}-services"
  description = "ECS tasks: reachable only from the load balancer"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "services_from_alb" {
  for_each = local.container_ports

  security_group_id            = aws_security_group.services.id
  description                  = "Traffic on port ${each.value} from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}

# No rule reaches the whole internet. AWS APIs stay inside the VPC: the interface endpoints (ECR, CloudWatch Logs,
# Secrets Manager) and the internal load balancer sit in the VPC CIDR, and image layers come from S3 through the
# gateway endpoint. Only the parcel carrier's published addresses leave through the NAT gateways.
resource "aws_vpc_security_group_egress_rule" "services_https_vpc" {
  security_group_id = aws_security_group.services.id
  description       = "HTTPS to the interface endpoints and the internal load balancer"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "services_https_s3" {
  security_group_id = aws_security_group.services.id
  description       = "HTTPS to Amazon S3 through the gateway endpoint (ECR image layers)"
  prefix_list_id    = var.s3_prefix_list_id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "services_https_carrier" {
  for_each = toset(var.carrier_api_cidrs)

  security_group_id = aws_security_group.services.id
  description       = "HTTPS to the parcel carrier label API at ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "services_postgres" {
  security_group_id = aws_security_group.services.id
  description       = "PostgreSQL inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = var.services

  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "execution" {
  name = "${var.name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = local.has_secrets ? 1 : 0

  name = "read-service-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = local.secret_arns
      },
      {
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = var.kms_key_arn
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.region}.amazonaws.com" } }
      },
    ]
  })
}

# The tasks call no AWS API themselves, so their role carries no permissions. A separate role keeps it that way
# even if the execution role grows.
resource "aws_iam_role" "task" {
  name = "${var.name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                   = each.key
    image                  = each.value.image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "10001"
    portMappings           = [{ containerPort = each.value.container_port, protocol = "tcp" }]
    environment            = [for k, v in each.value.environment : { name = k, value = v }]
    secrets                = [for k, v in each.value.secrets : { name = k, valueFrom = v }]
    mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.service[each.key].name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = each.key
      }
    }
  }])

  volume {
    name = "tmp"
  }
}

resource "aws_ecs_service" "this" {
  for_each = var.services

  name                              = each.key
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.this[each.key].arn
  desired_count                     = each.value.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 60
  propagate_tags                    = "SERVICE"
  enable_execute_command            = false

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this[each.key].arn
    container_name   = each.key
    container_port   = each.value.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.https]
}
