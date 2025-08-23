#!/bin/bash

set -euo pipefail

cd "$(readlink -f "$(dirname -- "$0")")"

readonly OWNER=${1:-"ryoppippi"}
readonly REPO=${2:-"ccusage"}

gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/${OWNER}/${REPO}/dependency-graph/sbom"


