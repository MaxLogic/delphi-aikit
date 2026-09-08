"""Enforce the retained semantic-workflow budgets on real benchmark summaries."""
import argparse
import json
import math
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summaries", type=Path, nargs="+")
    parser.add_argument("--smoke", action="store_true",
                        help="Check one or more cold remove-with runs during development.")
    args = parser.parse_args()
    budgets = {
        ("remove-with-plan-all", "cold"): (5, 22.0, None),
        ("remove-with-plan-all", "warm"): (10, 10.0, None),
        ("rename-dry-run-allfiles", "cold"): (5, 55.0, None),
        ("rename-dry-run-allfiles", "warm"): (10, 2.0, 2.5),
    }
    if args.smoke:
        budgets = {("remove-with-plan-all", "cold"): (1, 22.0, None)}
    rows = []
    for path in args.summaries:
        results = json.loads(path.read_text(encoding="utf-8-sig"))["results"]
        rows.extend([results] if isinstance(results, dict) else results)
    failures = []
    for (workflow, mode), (runs, median_limit, p95_limit) in budgets.items():
        matches = [row for row in rows if row["Id"] == workflow and row["CacheMode"] == mode]
        label = f"{workflow} {mode}"
        if len(matches) != 1:
            failures.append(f"{label}: expected exactly one summary row, found {len(matches)}")
            continue
        row = matches[0]
        if (row["Runs"] < runs or row["Status"] != "passed" or row["ExitCode"] != 0
                or row["SourceMutationStatus"] != "clean"):
            failures.append(f"{label}: requires {runs} successful runs with unchanged source")
            continue
        for field, limit in (("MedianSeconds", median_limit), ("P95Seconds", p95_limit)):
            if limit is None:
                continue
            value = row[field]
            if (isinstance(value, bool) or not isinstance(value, (int, float))
                    or not math.isfinite(value) or value < 0 or value > limit):
                failures.append(f"{label}: {field}={value}, budget={limit} seconds")
        print(f"{label}: n={row['Runs']}, median={row['MedianSeconds']} s, "
              f"p95={row['P95Seconds']} s")
    for failure in failures:
        print("FAIL:", failure)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
