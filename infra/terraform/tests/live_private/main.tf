# Test-only root. Its test file plans ../live, the live-test root, with the mock provider and asserts that the live
# test creates nothing internet-facing. `make verify` runs it with the other terraform test roots.
