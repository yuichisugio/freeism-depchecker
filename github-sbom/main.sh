#!/bin/bash

#--------------------------------------
# GitHub Dependency Graph の SBOM を取得して、purl形式で、依存ライブラリを出力する
#--------------------------------------

#--------------------------------------
# 準備（エラー対応、相対PATH安定、依存コマンドの確認、gh 認証確認）
#--------------------------------------
set -euo pipefail

# 相対PATHを安定させる
cd "$(cd "$(dirname -- "$0")" && pwd -P)"

# 依存コマンドの確認
for cmd in curl gh jq; do
  if ! command -v "$cmd" >/dev/null; then
    echo "ERROR: $cmd が必要です。" >&2
    exit 1
  fi
done

# gh 認証確認
if ! gh auth status >/dev/null; then
  echo "ERROR: gh が認証されていません。" >&2
  exit 1
fi

#--------------------------------------
# 使い方の表示
#--------------------------------------
if [[ ("${1:-}" == "-h" || "${1:-}" == "--help") ]]; then
  cat <<EOF
Usage:
  $0 [OWNER] [REPO]

Description:
  「GitHubのDependency Graph」を用いて依存からソースリポジトリを解決します。

Options:
  -h, --help   ヘルプ
  -r, --ratelimit レートリミット表示

Output:
  ${OUTPUT_JSON}

Examples:
  $0 ryoppippi ccusage
EOF
  exit 0
fi

#--------------------------------------
# レートリミット
#--------------------------------------
if [[ ("${1:-}" == "-r" || "${1:-}" == "--ratelimit") ]]; then
  gh api -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /rate_limit |
    jq '.resources.dependency_sbom
          | .reset |= (strftime("%Y-%m-%d %H:%M:%S UTC"))'
  exit 0
fi

#--------------------------------------
# 引数の取得
#--------------------------------------
readonly OWNER=${1:-"ryoppippi"}
readonly REPO=${2:-"ccusage"}

#--------------------------------------
# 出力ファイル・フォルダの準備
#--------------------------------------
# タイムスタンプ
# shellcheck disable=SC2155
readonly TS="$(date +%Y%m%d_%H%M%S)"

# 出力フォルダを作成
readonly RESULTS_DIR="./results/${OWNER}_${REPO}"
mkdir -p "${RESULTS_DIR}/raw-data" "${RESULTS_DIR}/formatted-data"

# 出力ファイル名を定義
readonly RAW_SBOM_JSON="${RESULTS_DIR}/raw-data/raw_${TS}.json"
readonly FORMATTED_JSON="${RESULTS_DIR}/formatted-data/output_${TS}.json"

#--------------------------------------
# 1) SBOM の取得
#--------------------------------------
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/${OWNER}/${REPO}/dependency-graph/sbom" |
  jq '.' >"${RAW_SBOM_JSON}"

#--------------------------------------
# 2) purl 抽出
#--------------------------------------
mapfile -t PURL_RAW_ARR < <(
  jq -r '
    .sbom.packages[]
    | (.externalRefs // [])
    | map(select(.referenceType=="purl"))[]
    | .referenceLocator
    | sub("^pkg:"; "")
    | @%5E/
    | map(
        capture("^(?<host>[^/]+)/(?<namever>.+)$")
        | .repo = (
            .namever
            | if test("@[^@]+$") then
                capture("^(?<name>.+)@(?<ver>[^@]+)$") | "\(.name)\(.ver)"
              else .
              end
          )
        | {host, repo}
      )
    | unique_by(.host + ":" + .repo)
  ' "${RAW_SBOM_JSON}" | sort -u
)

#--------------------------------------
# 3) 指定フォーマットで出力
#--------------------------------------
jq -n \
  --arg createdAt "${TS}" \
  --arg owner "${OWNER}" \
  --arg Repository "${REPO}" \
  --argjson libraries "${PURL_RAW_ARR[@]}" '
{
  meta: {
    createdAt: $createdAt,
    "specified-oss": { owner: $owner, Repository: $Repository }
  },
  data: $libraries
}
' | jq . >"${FORMATTED_JSON}"
