#!/usr/bin/env bash
set -euo pipefail

# Print the CHANGELOG.md section body for a given version (Keep a Changelog
# format: headings like "## [1.1.1] - 2026-06-17"). Exits 1 if not found.
# Usage: scripts/changelog-section.sh <version>    e.g. 1.1.1

VERSION="${1:?usage: scripts/changelog-section.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"

section="$(awk -v ver="$VERSION" '
  $0 ~ ("^## \\[" ver "\\]") { grab=1; next }
  grab && /^## \[/ { exit }
  grab { print }
' "$CHANGELOG")"

if [ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
  echo "No CHANGELOG section for version $VERSION" >&2
  exit 1
fi

printf '%s\n' "$section"
