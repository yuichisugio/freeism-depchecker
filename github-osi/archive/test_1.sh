#!/bin/bash

set -euo pipefail

cd "$(readlink -f "$(dirname -- "$0")")"

readonly OWNER=${1:-"ryoppippi"}
readonly REPO=${2:-"ccusage"}

gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/${OWNER}/${REPO}/dependency-graph/sbom" |
  jq -r '
  .sbom as $s
  | (# rootのID を特定)
    ($s.relationships[]
     | select(.relationshipType=="DESCRIBES" and .spdxElementId=="SPDXRef-DOCUMENT")
     | .relatedSpdxElement) as $root
  | (# SPDXID -> package の辞書)
    ($s.packages
     | map({key:.SPDXID, value:{name:.name,
         purl:(.externalRefs[]? | select(.referenceType=="purl") | .referenceLocator)}})
     | from_entries) as $pkg
  | (# root から1本の DEPENDS_ON)
    [ $s.relationships[] | select(.relationshipType=="DEPENDS_ON" and .spdxElementId==$root)
      | .relatedSpdxElement ] as $direct
  | $direct[]
  | $pkg[.] | "\(.name)\t\(.purl)"
  '
