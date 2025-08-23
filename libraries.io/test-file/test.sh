#!/bin/bash

set -euo pipefail
cd "$(readlink -f "$(dirname -- "$0")")"

raw_json="$1"

libs_tmp=$(mktemp)
trap 'rm -f "$libs_tmp"' EXIT
printf '%s\n' "$libs_tmp"

function get_repo_info() {
  local url
  url="https://libraries.io/api/${1}/$(printf '%s' "${2}" | jq -sRr '@uri')"

  curl -sS "${url}" | jq '.'
  return 0
}

while IFS=$'\t' read -r platform project_name; do
  printf '%s %s\n' "$platform" "$project_name"

  repo_info=$(get_repo_info "$platform" "$project_name")

  repo_url=$(printf '%s' "$repo_info" | jq -r '(.repository_url // .source_code_url // .github_repo_url // .homepage // "")')

  printf '%s\n' "$repo_url"

done < <(
  jq -r '
    # 1) 依存配列を安全に取り出し（なければ空配列）
    .dependencies // []

    # 2) 配列内の各要素オブジェクトを順番に取り出して、次のパイプに渡す
    | .[]

    # 3) 出力したい2列（配列）を作る。@tsv は配列を1行のタブ区切り文字列に変換するためのもの。
    | [.platform, .project_name] 

    # 4) 1行TSVに整形
    | @tsv
  ' "$raw_json"
)
