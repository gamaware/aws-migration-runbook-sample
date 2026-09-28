# Offline guard for the live test (ADR 0005). It plans the real live-test root, infra/terraform/tests/live, with the
# mock provider, so no credentials or network access are needed, and fails if that root would create anything
# internet-facing: an internet gateway, a public NAT gateway, an Elastic IP, a default route, a subnet that maps
# public IP addresses, a public database or database ingress from 0.0.0.0/0 or ::/0. The live root has no load
# balancer and no ECS service; scripts/check_private_plan.py refuses those in the real plan if one is ever added.
mock_provider "aws" {
  source = "../mocks"
}

variables {
  aws_profile = "offline-mock"
  run_id      = "offline1"
}

run "live_root_is_private_only" {
  command = plan

  module {
    source = "../live"
  }

  assert {
    condition     = output.internet_exposure.internet_gateways == 0 && output.internet_exposure.elastic_ips == 0
    error_message = "The live test must not create an internet gateway or Elastic IP addresses."
  }

  assert {
    condition     = output.internet_exposure.public_nat_gateways == 0
    error_message = "The live test must not create a public NAT gateway."
  }

  assert {
    condition     = output.internet_exposure.default_routes == 0
    error_message = "The live test must not create a default route (0.0.0.0/0) to an internet or NAT gateway."
  }

  assert {
    condition     = output.internet_exposure.public_ip_subnets == 0
    error_message = "No live-test subnet may map public IP addresses on launch."
  }

  assert {
    condition     = output.database_publicly_accessible == false
    error_message = "The live-test database must not be publicly accessible."
  }

  assert {
    condition     = length(setintersection(output.database_ingress_cidrs, ["0.0.0.0/0", "::/0"])) == 0
    error_message = "The live-test database must not accept ingress from 0.0.0.0/0 or ::/0."
  }
}
