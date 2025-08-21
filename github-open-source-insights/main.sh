#!/bin/bash

# GitHubのDependency Graph の SBOM を取得するファイル

set -euo pipefail

cd "$(dirname "$0")"

# デフォルト設定
readonly OWNER=${1:-"yoshiko-pg"}
readonly REPO=${2:-"difit"}
readonly RESULTS_DIR="./results"

# 使用方法の表示
show_usage() {
  cat <<EOF
    Usage:
      $0 [OWNER] [REPO]

    Description:
      Google Open Source Insightsから依存関係を取得します。

    Parameters:
      OWNER    リポジトリのオーナー名          (デフォルト: yoshiko-pg)
      REPO     リポジトリ名                   (デフォルト: difit)

    Options:
      -h, --help   ヘルプを表示

    Output:
      - dependency.json

    Examples:
      $0 yoshiko-pg difit
EOF

  return 0
}

# ヘルプオプションの処理。引数がある場合のみヘルプをチェック。
# 引数がない場合はヘルプを表示しない。
if [[ $# -gt 0 && ("$1" == "-h" || "$1" == "--help") ]]; then
  show_usage
  exit 0
fi

# 出力ディレクトリの準備
setup_output_directory() {
  # 出力ディレクトリが存在しない場合は作成
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  return 0
}

# リポジトリのバージョンを取得
function get_repo_version() {
  # リポジトリのバージョンを取得
  local version
  version=$(curl "https://api.deps.dev/v3/projects/github.com%2F${OWNER}%2F${REPO}:packageversions" |
    tee "${RESULTS_DIR}/raw-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json" |
    jq -r '.versions[0].version')
  echo "${version}"

  return 0
}

# データを取得する関数
function get_repo_info() {
  # Google Open Source Insights から、指定リポジトリの依存関係を取得
  echo "Google Open Source Insights から、指定リポジトリの依存関係を取得"
  curl "https://api.deps.dev/v3/systems/NPM/packages/react/versions/${repo_version}:dependencies" |
    tee "${RESULTS_DIR}/raw-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  return 0
}

# 依存ライブラリごとに、ホスティングサービスのowner/repoを取得
function get_repo_dependency() {
  # 依存ライブラリごとに、ホスティングサービスのowner/repoを取得
  echo "依存ライブラリごとに、ホスティングサービスのowner/repoを取得"
  curl "https://api.deps.dev/v3/systems/NPM/packages/scheduler/versions/${repo_version}" |
    tee "${RESULTS_DIR}/raw-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  return 0
}

# メイン関数
function main() {
  # 出力ディレクトリの準備
  setup_output_directory

  # データを取得
  repo_version=$(get_repo_version)
  repo_info=$(get_repo_info)
  repo_dependency=$(get_repo_dependency)

  # データを処理
  process_data "$repo_version" "$repo_info" "$repo_dependency"

  return 0
}

# スクリプトを実行
main


#!/bin/bash

# GitHubのDependency Graph の SBOM を取得するファイル

set -euo pipefail

cd "$(dirname "$0")"

# デフォルト設定
readonly OWNER=${1:-"yoshiko-pg"}
readonly REPO=${2:-"difit"}
readonly RESULTS_DIR="./results"

# 使用方法の表示
show_usage() {
  cat <<EOF
    Usage:
      $0 [OWNER] [REPO]

    Description:
      GitHub リポジトリの Dependency Graph の SBOM を取得します。

    Parameters:
      OWNER    リポジトリのオーナー名          (デフォルト: yoshiko-pg)
      REPO     リポジトリ名                   (デフォルト: difit)

    Options:
      -h, --help   ヘルプを表示

    Output:
      - dependency.json

    Examples:
      $0 yoshiko-pg difit
EOF

  return 0
}

# ヘルプオプションの処理。引数がある場合のみヘルプをチェック。
# 引数がない場合はヘルプを表示しない。
if [[ $# -gt 0 && ("$1" == "-h" || "$1" == "--help") ]]; then
  show_usage
  exit 0
fi

# 出力ディレクトリの準備
setup_output_directory() {
  # 出力ディレクトリが存在しない場合は作成
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  return 0
}

# データを取得する関数
function get_raw_data() {
  # GitHub API から、指定リポジトリのGitHub dependency graph の SBOM を取得
  echo "GitHub API から、指定リポジトリのGitHub dependency graph の SBOM を取得"
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/"${OWNER}"/"${REPO}"/dependency-graph/sbom \
    | tee "${RESULTS_DIR}/raw-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  return 0
}

# データを処理する関数
function process_data() {
  # データを処理
  echo "データを処理します"
  echo "$1"
  return 0
}

# メイン関数
function main() {
  # 出力ディレクトリの準備
  setup_output_directory

  # データを取得
  raw_data=$(get_raw_data)

  # データを処理
  process_data "$raw_data"

  return 0
}

# スクリプトを実行
main
