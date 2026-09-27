# Real AWS, run only by `make test-live`. terraform test destroys everything after the last run block.

run "wave_one_foundation_applies" {
  command = apply

  assert {
    condition     = can(regex("\\.rds\\.amazonaws\\.com$", output.database_address))
    error_message = "RDS did not return an endpoint."
  }

  assert {
    condition     = startswith(output.vpn_connection_id, "vpn-")
    error_message = "AWS rejected the VPN connection or its tunnel options."
  }
}
