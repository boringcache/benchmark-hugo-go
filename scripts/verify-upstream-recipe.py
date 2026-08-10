#!/usr/bin/env python3
"""Fail when the committed Hugo Go plan drifts from pinned upstream CI."""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = ["env", "GOARCH=amd64", "GOOS=dragonfly", "go", "install"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    try:
        plan = tomllib.loads((ROOT / ".boringcache.toml").read_text())
        require(plan["adapters"]["go"]["command"] == EXPECTED, "Go plan changed")
        upstream = (ROOT / "upstream/.github/workflows/test.yml").read_text()
        for fragment in ("name: Build for dragonfly", "go install", "go clean -i -cache", "GOARCH: amd64", "GOOS: dragonfly"):
            require(fragment in upstream, f"upstream Hugo phase changed: {fragment}")
        action = (ROOT / ".github/actions/hugo-go-benchmark/action.yml").read_text()
        require("run-benchmark-plan.py go --working-directory upstream" in action, "workflow bypasses the plan")
    except (KeyError, OSError, RuntimeError, tomllib.TOMLDecodeError) as error:
        print(f"Hugo Go recipe mismatch: {error}", file=sys.stderr)
        return 1
    print("Verified Hugo's DragonFly go install plan against pinned upstream CI.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
