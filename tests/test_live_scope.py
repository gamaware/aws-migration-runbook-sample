"""The live-test root creates nothing public and no Route 53 resource (ADR 0005).

The weighted-record cutover (ADR 0003) stays in the offline plan and the mock-provider tests; the live root and every
module it calls must not declare an aws_route53_* resource.
"""

import re
from pathlib import Path

TERRAFORM = Path(__file__).resolve().parents[1] / "infra" / "terraform"
LIVE_ROOT = TERRAFORM / "tests" / "live"
SOURCE = re.compile(r'^\s*source\s*=\s*"(\.[^"]+)"', re.MULTILINE)
RESOURCE = re.compile(r'^\s*resource\s+"(aws_[a-z0-9_]+)"', re.MULTILINE)


def module_dirs(root: Path) -> list[Path]:
    """The root plus every local module it calls, directly or through other modules."""
    seen: list[Path] = []
    pending = [root.resolve()]
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.append(current)
        for tf in current.glob("*.tf"):
            pending.extend((current / source).resolve() for source in SOURCE.findall(tf.read_text()))
    return seen


def resource_types(root: Path) -> set[str]:
    return {rtype for d in module_dirs(root) for tf in d.glob("*.tf") for rtype in RESOURCE.findall(tf.read_text())}


def test_live_root_calls_known_modules():
    names = {d.name for d in module_dirs(LIVE_ROOT)}
    assert {"live", "network", "database"} <= names
    assert "dns" not in names


def test_live_root_declares_no_route53_resource():
    route53 = sorted(t for t in resource_types(LIVE_ROOT) if t.startswith("aws_route53"))
    assert route53 == []


def test_scan_sees_route53_in_production():
    """Guards the scan itself: the production root does declare Route 53 records."""
    assert any(t.startswith("aws_route53") for t in resource_types(TERRAFORM / "envs" / "production"))
