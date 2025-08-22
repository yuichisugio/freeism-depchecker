#!/bin/bash

# Libraries.io から依存関係を取得するファイル

########################################
# 設定
########################################

# エラー検知、パイプラインのエラー検知、未定義変数のエラー検知で、即時停止
set -euo pipefail

# スクリプトのディレクトリに移動。相対PATHを安定させる。
cd "$(dirname "$0")"

# curlのインストールを確認
if ! command -v curl >/dev/null; then
  echo "ERROR: curlが必要です。" >&2
  exit 1
fi

# jqのインストールを確認
if ! command -v jq >/dev/null; then
  echo "ERROR: jq が必要です。" >&2
  exit 1
fi

# 引数: OWNER / REPO / SERVICE(github|gitlab|bitbucket)
readonly OWNER=${1:-"yoshiko-pg"}
readonly REPO=${2:-"difit"}
readonly SERVICE=${3:-"github"}
readonly RESULTS_DIR="./results"

########################################
# ヘルプ表示
########################################

# 使用方法の表示
show_usage() {
  cat <<EOF
    Usage:
      $0 [OWNER] [REPO] [SERVICE]

    Description:
      Libraries.io から依存関係を取得し、README 記載の JSON 形式で results/dependency.json を出力します。

    Parameters:
      OWNER    リポジトリのオーナー名           (デフォルト: yoshiko-pg)
      REPO     リポジトリ名                    (デフォルト: difit)
      SERVICE  ホスティングサービス名           (デフォルト: github)

    Options:
      -h, --help   ヘルプを表示

    Output:
      - results/raw-*.json
      - results/dependency.json

    Examples:
      $0 yoshiko-pg difit github
EOF

  return 0
}

# ヘルプオプションの処理。引数がある場合のみヘルプをチェック。引数がない場合はデフォルト値を使用するので、ヘルプを表示しない。
if [[ $# -gt 0 && ("$1" == "-h" || "$1" == "--help") ]]; then
  show_usage
  exit 0
fi

########################################
# 共通ユーティリティ
########################################

# 出力ディレクトリの作成
setup_output_directory() {
  # RESULTS_DIRディレクトリが存在しない場合は作成
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  # REPOディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}"
  fi

  # raw-dataディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/raw-data" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/raw-data"
  fi

  # formatted-dataディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/formatted-data" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/formatted-data"
  fi

  return 0
}

# リポジトリ URL から host/owner/repo を抽出
parse_repo_url() {
  # 入力: $1 = repository_url
  local input="$1"
  local u host path owner repo

  # 余計なプレフィックス・サフィックスを除去
  u="${input#git+}"
  u="${u%.git}"

  # 形式に応じて host/path を分解
  if [[ "$u" =~ ^git@([^:]+):(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$u" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$u" =~ ^https?://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  # owner/repo 形式へ
  path="${path%.git}"
  owner="${path%%/*}"
  repo="${path#*/}"
  repo="${repo%%/*}"

  if [[ -z "$host" || -z "$owner" || -z "$repo" ]]; then
    return 1
  fi

  # 出力: JSON 1 行
  jq -n --arg host "$host" --arg owner "$owner" --arg repo "$repo" '{host:$host, owner:$owner, repo:$repo}'
}


########################################
# データ取得
########################################
get_dependencies_raw() {
  # 指定リポジトリの依存関係（libraries.io）を取得
  echo "Libraries.io から依存関係を取得: ${SERVICE}/${OWNER}/${REPO}"
  local url
  url="https://libraries.io/api/${SERVICE}/${OWNER}/${REPO}/dependencies"
  local raw_file
  raw_file="${RESULTS_DIR}/${REPO}/raw-data/${SERVICE}-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"
  # 取得結果をファイルへ保存しつつ内容を標準出力へ返す
  curl -sS "$url" | tee "$raw_file"
}


########################################
# 加工・保存
########################################
process_raw_data() {
  # $1: 依存関係の raw JSON
  local raw_json="$1"

  # 依存ライブラリの (platform, name) を抽出
  # 一部の platform/name は repository_url が無い場合があるため、その場合はスキップ
  local libs_tmp
  libs_tmp=$(mktemp)
  trap 'rm -f "$libs_tmp"' EXIT

  # 依存の配列を反復処理
  echo "$raw_json" | jq -r '.dependencies // [] | .[] | "\(.platform)\t\(.name)"' | while IFS=$'\t' read -r platform name; do
    # 各依存について repository_url を取得
    local encoded
    echo -n "${name}" | jq -sRr @uri
    encoded=$(url_encode "$name")
    local url
    url="https://libraries.io/api/${platform}/${encoded}"
    # repository_url / source_code_url など候補を順に採用
    repo_url=$(curl -sS "${url}" | jq -r '(.repository_url // .source_code_url // .github_repo_url // .homepage // "")')
    if [[ -z "${repo_url}" || "${repo_url}" == "null" ]]; then
      continue
    fi
    # host/owner/repo に分解
    parsed=$(parse_repo_url "$repo_url" || true)
    if [[ -n "${parsed}" ]]; then
      echo "$parsed" >>"$libs_tmp"
    fi
  done

  # 収集した JSON 行を配列へ
  local libs_array
  if [[ -s "$libs_tmp" ]]; then
    libs_array=$(jq -s '.' "$libs_tmp")
  else
    libs_array='[]'
  fi

  # 出力 JSON を構築
  local formatted_output_json
  formatted_output_json=$(jq -n \
    --arg createdAt "$(date +%Y-%m-%d)" \
    --arg owner "$OWNER" \
    --arg repo "$REPO" \
    --argjson libs "$libs_array" \
    '{
      meta: {
        createdAt: $createdAt,
        "destinated-oss": { owner: $owner, Repository: $repo }
      },
      data: {
        libraries: [ $libs ]
      }
    }')

  # 結果を返す
  echo "$formatted_output_json"
  return 0
}

# 出力を保存
save_output() {
  # $1: 出力 JSON
  local json="$1"
  local out_file="${RESULTS_DIR}/${REPO}/formatted-data/dependency.json"
  echo "$json" | jq '.' >"$out_file"
  echo "Saved: $out_file"
}

# 実行の流れを定義
main() {
  setup_output_directory
  # 1) 依存関係の raw を取得
  raw_data=$(get_dependencies_raw)
  # 2) README 形式に整形
  output_json=$(process_raw_data "$raw_data")
  # 3) 保存
  save_output "$output_json"
  return 0
}

# スクリプトを実行
main
