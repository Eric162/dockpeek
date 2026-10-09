#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/tools.sh
# A dedicated, clean build is required; incremental logs silently miss files.
scratch=.build/analysis
mkdir -p .build/reports
swift package --scratch-path "$scratch" clean
swift build --scratch-path "$scratch" --verbose > .build/reports/compiler.log 2>&1 || {
  cat .build/reports/compiler.log >&2
  exit 1
}
./scripts/test.sh --scratch-path "$scratch" --verbose >> .build/reports/compiler.log 2>&1 || {
  cat .build/reports/compiler.log >&2
  exit 1
}
"$SWIFTLINT" analyze --strict --config .swiftlint.yml --compiler-log-path .build/reports/compiler.log > .build/reports/analysis.log 2>&1 || {
  grep -E "error:|warning:|Skipping|Done analyzing" .build/reports/analysis.log >&2 || tail -30 .build/reports/analysis.log >&2
  exit 1
}
grep -E "Analyzing|Done analyzing|error:|warning:" .build/reports/analysis.log
# Fail if SourceKit could not match a file to its compiler invocation.
if grep -Ei 'skipping|could not|couldn.t|error:' .build/reports/analysis.log; then
  echo 'Static analysis did not cover every Swift file.' >&2
  exit 1
fi
python3 - <<'VERIFY'
import re
from pathlib import Path
expected = sum(len(list(Path(root).rglob("*.swift"))) for root in ("Sources", "Tests", "Experiments"))
log = Path(".build/reports/analysis.log").read_text()
summary = re.search(r"Done analyzing! Found 0 violations, 0 serious in (\d+) files\.", log)
if not summary or int(summary.group(1)) != expected:
    raise SystemExit("Static analysis must successfully check every source, test, and experiment file")
VERIFY
