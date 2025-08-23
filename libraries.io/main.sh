#!/bin/bash

# Libraries.io から依存関係を取得するファイル

########################################
# 設定
########################################

# エラー検知、パイプラインのエラー検知、未定義変数のエラー検知で、即時停止
set -euo pipefail

# スクリプトのディレクトリに移動。相対PATHを安定させる。
cd "$(readlink -f "$(dirname -- "$0")")"

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
function show_usage() {
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
# 出力ディレクトリの作成
########################################
function setup_output_directory() {
  # RESULTS_DIRディレクトリが存在しない場合は作成
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  # REPOディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}"
  fi

  # raw-data/dependenciesディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/raw-data/dependencies" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/raw-data/dependencies"
  fi

  # raw-data/repo-infoディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/raw-data/repo-info" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/raw-data/repo-info"
  fi

  # formatted-dataディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/formatted-data" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/formatted-data"
  fi

  return 0
}

########################################
# データ取得
########################################

# 依存関係のデータを取得
function get_dependencies() {
  # 指定リポジトリの依存関係（libraries.io）を取得
  local url
  url="https://libraries.io/api/${SERVICE}/${OWNER}/${REPO}/dependencies"

  # 出力PATHを作成
  local raw_file
  raw_file="${RESULTS_DIR}/${REPO}/raw-data/dependencies/${SERVICE}-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  # 取得結果をファイルへ保存しつつ内容を標準出力へ返す
  curl -sS "$url" | tee "$raw_file"

  return 0
}

# 依存関係のデータのホスティングサービス内のURLを取得
function get_repo_info() {
  # $1: パッケージマネージャー名
  # $2: プロジェクト名

  # リポジトリ情報を取得
  # -nは、echoにデフォで入る改行コードを削除するために必要。
  # jqの'@uri'は、URLエンコードを行う。-sは改行込みで取り込む。-RはJSONではなく文字列で出力。-rはJSONではなく文字列で取り込む
  local url
  url="https://libraries.io/api/${1}/$(printf '%s' "${2}" | jq -sRr '@uri')"

  # 出力PATHを作成
  local raw_file
  raw_file="${RESULTS_DIR}/${REPO}/raw-data/repo-info/${1}-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  # 取得結果をファイルへ保存しつつ内容を標準出力へ返す
  # jq '.'は、JSONを綺麗に出力するために必要。
  # curl -sSは、-sがサイレント、-Sがエラー時のみサイレント解除
  curl -sS "${url}" | tee "$raw_file" | jq '.'
  return 0
}

########################################
# データ抽出
########################################

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

########################################
# 加工
########################################
function process_raw_data() {
  # $1: 依存関係の raw JSON
  local raw_json="$1"

  local libs_array=()

  # 依存ライブラリの (platform, name) を抽出
  while IFS=$'\t' read -r platform project_name; do

    # 各依存について repository_urlのAPIで取得
    local repo_info
    repo_info=$(get_repo_info "$platform" "$project_name")

    # repository_url / source_code_url など候補を順に採用
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

  # 結果を返す
  tee "$formatted_output_json" | jq '.'
  return 0
}

########################################
# 保存
########################################
function save_output() {
  # $1: 出力 JSON
  local json="$1"
  local out_file="${RESULTS_DIR}/${REPO}/formatted-data/dependency.json"
  echo "$json" | jq '.' >"$out_file"
  echo "Saved: $out_file"
}

########################################
# 実行の流れを定義
########################################
function main() {
  # 出力ディレクトリの作成
  setup_output_directory

  # 1) 依存関係の raw を取得
  local raw_data
  raw_data=$(get_dependencies)

  # 2) README 形式に整形
  local output_json
  output_json=$(process_raw_data "$raw_data")

  # 3) 保存
  save_output "$output_json"

  return 0
}

########################################
# スクリプトを実行
########################################
main
