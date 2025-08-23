#!/bin/bash

set -euo pipefail
cd "$(readlink -f "$(dirname -- "$0")")"

raw_json="$1"

libs_tmp=$(mktemp)
trap 'rm -f "$libs_tmp"' EXIT
echo "$libs_tmp"

while IFS=$'\t' read -r platform project_name; do
  if [[ -z "$platform" || -z "$project_name" ]]; then
    printf 'skip: %s %s\n' "$platform" "$project_name"
    continue
  fi
  printf '%s %s\n' "$platform" "$project_name"
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
