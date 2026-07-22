#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
maximum_lines="${MAX_SWIFT_FILE_LINES:-500}"

if ! [[ "$maximum_lines" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: MAX_SWIFT_FILE_LINES must be a positive integer" >&2
  exit 2
fi

failures=0
while IFS= read -r file; do
  line_count="$(wc -l < "$project_root/$file" | tr -d '[:space:]')"
  if (( line_count > maximum_lines )); then
    echo "error: $file has $line_count lines (limit: $maximum_lines)" >&2
    failures=1
  fi
done < <(
  cd "$project_root"
  find Sources Tests -type f -name '*.swift' -print | LC_ALL=C sort
)

if (( failures != 0 )); then
  exit 1
fi

echo "Swift source size check passed (maximum $maximum_lines lines per file)."
