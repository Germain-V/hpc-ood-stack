#!/usr/bin/env bash
set -euo pipefail

# build.sh — Produce HPC-stack.zip containing only the tracked stack files
# Usage: ./build.sh [ref]
#   ref: optional git ref (commit/branch/tag). Defaults to HEAD.

REF=${1:-HEAD}
OUTPUT="HPC-stack.zip"

# Ensure we are in the repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "${REPO_ROOT}" ]; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi
cd "${REPO_ROOT}"

# Create or overwrite the archive from tracked files only
git archive --format=zip -o "${OUTPUT}" "${REF}"

echo "Created ${OUTPUT} from ${REF} at ${REPO_ROOT}"

