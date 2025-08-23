#!/bin/bash

set -euo pipefail
cd "$(readlink -f "$(dirname -- "$0")")"

raw_json="$1"
libs_array=()

function get_repo_info() {
  local url
  url="https://libraries.io/api/${1}/$(printf '%s' "${2}" | jq -sRr '@uri')"
  curl -sS "${url}" | jq '.'
  return 0
}

# リポジトリURLを {host, owner, repo} に分解する
function parse_repo_url() {
  local url="$1"
  # jq -n: 標準入力を読まず null から評価。--arg u で $u に URL を渡す
  jq -cn --arg u "$url" '
    # まずスキームや www.、末尾の / を正規化
    ($u
      | sub("^git\\+https?://"; "https://")   # git+https:// → https://
      | sub("^https?://"; "")                 # スキーム除去
      | sub("^www\\."; "")                    # www. 除去
      | gsub("/+$"; "")                       # 末尾の / 群を除去
    ) as $norm
    # host/owner/repo/… に分割
    | ($norm | split("/")) as $p
    # 最低でも host, owner, repo の3要素が必要
    | if ($p|length) < 3 then empty else
        {
          host:  $p[0],
          owner: $p[1],
          # repo は .git, ?query, #fragment を除去
          repo:  ($p[2]
                   | sub("\\.git$"; "")
                   | split("?")[0]
                   | split("#")[0])
        }
      end
  '
  return 0
}

while IFS=$'\t' read -r platform project_name; do
  printf '%s %s\n' "$platform" "$project_name"

  repo_info="$(get_repo_info "$platform" "$project_name")"

  # repository_url, source_code_url, github_repo_url, homepage のうち最初に見つかったもの
  repo_url="$(printf '%s' "$repo_info" |
    jq -r '(.repository_url // .source_code_url // .github_repo_url // .homepage // empty)')"

  # URL がなければスキップ
  [[ -z "$repo_url" ]] && {
    echo "skip: no repo_url"
    continue
  }

  parsed="$(parse_repo_url "$repo_url")"

  # 解析に失敗（empty）ならスキップ
  [[ -z "$parsed" ]] && {
    echo "skip: parse failed ($repo_url)"
    continue
  }

  combined="$(
    jq -cn \
      --argjson base "$parsed" \
      --argjson info "$repo_info" \
      '
        # 取り出し（空なら ""）
        ($info.homepage // "")               as $homepage |
        ($info.package_manager_url // "")    as $pm       |
        ($info.repository_url // "")         as $repo_url |
        # base + 追加フィールド
        $base + {
          homepage:           $homepage,
          package_manager_url:$pm,
          repository_url:     $repo_url
        }
        # 値が空文字のキーは削除
        | with_entries(select(.value != ""))
      '
  )"

  # JSON 文字列を Bash 配列に追加（※要素は1オブジェクト）
  libs_array+=("$combined")
  printf '%s\n' "$combined"

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

# Bash配列(各行が JSON オブジェクト) → jq --slurp(-s) で JSON 配列へ
libs_json="$(printf '%s\n' "${libs_array[@]}" | jq -s '.')"

# 最終 JSON を組み立て（--arg は文字列、--argjson は JSON 値を受け取る）
formatted_output_json="$(
  jq -n \
    --arg createdAt "$(date +%Y-%m-%d)" \
    --arg owner "testOwner" \
    --arg repo "testRepo" \
    --argjson libs "$libs_json" \
    '{
      meta: {
        createdAt: $createdAt,
        "destinated-oss": { owner: $owner, repository: $repo }
      },
      data: { libraries: $libs }
    }'
)"

# 文字列として持っている JSON を整形して標準出力へ
printf '%s\n' "$formatted_output_json" | jq '.'
