#!/bin/bash

# Libraries.io から依存関係を取得するファイル

########################################
# 設定
########################################

# エラー検知、パイプラインのエラー検知、未定義変数のエラー検知で、即時停止
set -euo pipefail

# スクリプトのディレクトリに移動。相対PATHを安定させる。
cd "$(cd "$(dirname -- "$0")" && pwd -P)"

# 環境変数から API キーを受け取る（どちらか設定されていればOK）
# 例: export LIBRARIES_IO_API_KEY=xxxxx
API_KEY="${LIBRARIES_IO_API_KEY:-${LIBRARIES_API_KEY:-}}"
if [[ -z "${API_KEY:-}" ]]; then
  printf '%s\n' 'ERROR: Libraries.io の API キーが未設定です。「LIBRARIES_IO_API_KEY」 または「LIBRARIES_API_KEY」を設定してください。' >&2
  exit 1
fi

# 連続呼び出しの最小間隔（秒）。60req/min を超えないための保険。
RATE_LIMIT_DELAY="${RATE_LIMIT_DELAY:-1.2}"

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
# 共通: JSON専用のHTTP GET (429/503はリトライ)
########################################
# 使い方: http_get_json "<URL>" "<保存ファイルパス>"
# 成功時: 保存してから内容を標準出力に流す（= 呼び出し元で $(...) で受け取れる）
# 失敗時: 非0で return
function http_get_json() {
  local url="$1"
  local out="$2"
  local max_retries=5 # リトライ上限
  local attempt=1
  local headers tmp code ctype retry_after wait jitter_ms

  while :; do
    headers="$(mktemp)"
    tmp="$(mktemp)"

    # -D: ヘッダ保存, -o: 本文保存, -w: ステータスコード, -L: リダイレクト追従
    code="$(
      curl -sS -L -D "$headers" -o "$tmp" -w '%{http_code}' "$url" || true
    )"

    # Content-Type を取得（複数行ある場合もあるため最後を採用）
    ctype="$(
      awk 'BEGIN{IGNORECASE=1} /^content-type:/ {gsub(/\r/,""); sub(/^[^:]+:[[:space:]]*/,""); ct=$0} END{print tolower(ct)}' "$headers"
    )"
    retry_after="$(awk 'BEGIN{IGNORECASE=1} /^retry-after:/ {gsub(/\r/,""); print $2}' "$headers")"

    if [[ "$code" == "200" && "$ctype" == application/json* ]]; then
      # JSON 妥当性を軽くチェック
      if jq -e . "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$out"
        cat "$out" # 呼び出し元へJSONを返す
        rm -f "$headers"
        sleep "${RATE_LIMIT_DELAY:-0}"
        return 0
      fi
      # JSONが壊れている場合（まれ）
      echo "WARN: Invalid JSON in 200 response ($url)" >&2
      mv "$tmp" "${out}.invalid"
      rm -f "$headers"
      return 1
    fi

    # 429/503: レート制限 or 一時的エラー → バックオフしてリトライ
    if [[ "$code" == "429" || "$code" == "503" ]]; then
      # Retry-After があれば優先。無ければ指数バックオフ（1,2,4,8,16秒）＋±0-300msジッタ
      wait="${retry_after:-$((2 ** (attempt - 1)))}"
      jitter_ms=$((RANDOM % 300))
      echo "INFO: HTTP $code for $url. Retrying in ${wait}.${jitter_ms}s ..." >&2
      sleep "${wait}.$(printf '%03d' "$jitter_ms")"
      ((attempt++))
      if ((attempt > max_retries)); then
        echo "ERROR: Exceeded max retries for $url" >&2
        mv "$tmp" "${out}.errbody"
        rm -f "$headers"
        return 1
      fi
      rm -f "$headers" "$tmp"
      continue
    fi

    # 401/403: 認証・権限エラー（APIキー不備など）
    if [[ "$code" == "401" || "$code" == "403" ]]; then
      echo "ERROR: HTTP $code (auth). Check your Libraries.io API key. URL=$url" >&2
      mv "$tmp" "${out}.errbody"
      rm -f "$headers"
      return 1
    fi

    # その他のエラー
    echo "ERROR: HTTP $code for $url (ctype=$ctype). Body saved to ${out}.errbody" >&2
    mv "$tmp" "${out}.errbody"
    rm -f "$headers"
    return 1
  done
}

########################################
# 出力ディレクトリの作成
########################################
function setup_output_directory() {
  # RESULTS_DIRディレクトリが存在しない場合は作成
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  # REPOディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}" ]]; then
    mkdir -p "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}"
  fi

  # raw-data/dependenciesディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/raw-data/dependencies" ]]; then
    mkdir -p "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/raw-data/dependencies"
  fi

  # raw-data/repo-infoディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/raw-data/repo-info" ]]; then
    mkdir -p "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/raw-data/repo-info"
  fi

  # formatted-dataディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/formatted-data" ]]; then
    mkdir -p "${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/formatted-data"
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
  url="https://libraries.io/api/${SERVICE}/${OWNER}/${REPO}/dependencies?api_key=${API_KEY}"

  # 出力PATHを作成
  local raw_file
  raw_file="${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/raw-data/dependencies/${SERVICE}-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  # 成功時はファイルに保存し、ファイルパスを標準出力に返す
  if http_get_json "$url" "$raw_file" >/dev/null; then
    printf '%s\n' "${raw_file}"
    return 0
  else
    echo "ERROR: Failed to fetch dependencies from $url" >&2
    return 1
  fi
}

# 依存関係のデータのホスティングサービス内のURLを取得
function get_repo_info() {
  local platform="$1" # 例: npm, pypi など
  local project="$2"  # 例: react, pandas など

  # プロジェクト名はURLエンコード
  local encoded
  encoded="$(printf '%s' "${project}" | jq -sRr '@uri')"

  # リポジトリ情報を取得
  # -nは、echoにデフォで入る改行コードを削除するために必要。
  # jqの'@uri'は、URLエンコードを行う。-sは改行込みで取り込む。-RはJSONではなく文字列で出力。-rはJSONではなく文字列で取り込む
  local url
  url="https://libraries.io/api/${platform}/${encoded}?api_key=${API_KEY}"

  # ★ ファイル名用: スラッシュをハイフンに置換（@eslint/eslintrc → @eslint-eslintrc）
  #    Bashのパラメータ展開で「全部置換」: ${変数//検索/置換}
  # /のままだと、ファイル名になってしまうため、ハイフンに置換
  local project_file_name="${project//\//-}"
  local raw_file
  raw_file="${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/raw-data/repo-info/${platform}-${project_file_name}-$(date +%Y%m%d_%H%M%S).json"

  # ここで JSON を取得（429/503 は内部でリトライ）
  # 成功したら整形して標準出力に返す（呼び出し元の repo_info=$(...) に入る）
  http_get_json "$url" "$raw_file" | jq '.'
  return 0
}

########################################
# リポジトリURLを {host, owner, repo} に分解する
########################################
function parse_repo_url() {
  local url="$1"
  jq -cn --arg u "$url" '
    # ---------- 共通ユーティリティ ----------
    def strip_repo_suffix:
      sub("\\.git$"; "")         # 末尾 .git を除去
      | split("?")[0]            # ?query を除去
      | split("#")[0];           # #fragment を除去

    # SSH 形式: git@host:owner/repo(.git) を {host, owner, repo} に
    def parse_ssh($s):
      ( $s | capture("git@(?<host>[^:]+):(?<path>.+)") ) as $m
      | ($m.path | strip_repo_suffix | split("/") ) as $pp
      | if ($pp|length) >= 2 then
          { host: ($m.host|ascii_downcase), owner: $pp[0], repo: $pp[1] }
        else {host:"", owner:"", repo:""} end;

    # HTTP(S)/git:// などを https ベースのホスト/パスに正規化
    def normalize_http($s):
      $s
      | gsub("^git\\+https?://"; "https://")
      | gsub("^git://"; "https://")
      | gsub("^ssh://git@"; "https://")
      | sub("^https?://"; "")
      | sub("^www\\."; "")
      | gsub("/+$"; "");

    # GitLab: group/subgroup/repo/-/... → owner = group/subgroup, repo = repo
    def parse_gitlab($p):
      # 先頭(ホスト)を除いた配列
      ($p | map(select(. != ""))) as $pp
      | ($pp | index("-") // ($pp|length)) as $cut   # "/-/" 以降は不要
      | if $cut >= 3 then
          { host: ($p[0]|ascii_downcase),
            owner: ($pp[1:($cut-1)] | join("/")),
            repo:  ($pp[$cut-1] | strip_repo_suffix) }
        else
          # group/repo だけのケース
          if ($pp|length) >= 3 then
            { host: ($p[0]|ascii_downcase),
              owner: $pp[1],
              repo:  ($pp[2] | strip_repo_suffix) }
          else {host:"", owner:"", repo:""} end
        end;

    # Bitbucket Server: /projects/<KEY>/repos/<slug>/...
    def parse_bitbucket_server($p):
      if ($p|length) >= 5 and ($p[1]=="projects" and $p[3]=="repos") then
        { host: ($p[0]|ascii_downcase),
          owner: $p[2],
          repo:  ($p[4] | strip_repo_suffix) }
      else {host:"", owner:"", repo:""} end;

    # デフォルト（GitHub/Bitbucket Cloud 等）: /owner/repo/...
    def parse_default($p):
      if ($p|length) >= 3 then
        { host: ($p[0]|ascii_downcase),
          owner: $p[1],
          repo:  (($p[2] // "") | strip_repo_suffix) }
      else {host:"", owner:"", repo:""} end;

    # ---------- 実処理 ----------
    ($u // "") as $raw
    | if ($raw|length) == 0 then {host:"", owner:"", repo:""}
      elif ($raw | startswith("git@")) then
        parse_ssh($raw)
      else
        ( normalize_http($raw) ) as $norm
        | ($norm | split("/")) as $p
        | ($p[0] // "" | ascii_downcase) as $host
        | if $host == "api.github.com" and ($p|length) >= 4 and ($p[1] == "repos") then
            # GitHub API: api.github.com/repos/:owner/:repo
            { host: "github.com",
              owner: $p[2],
              repo:  ($p[3] | strip_repo_suffix) }
          elif $host == "github.com" then
            # GitHub: github.com/:owner/:repo/(blob|tree|...)/...
            parse_default($p)
          elif ($host|test("(^|\\.)gitlab\\.[^/]+$")) then
            # GitLab / self-hosted GitLab
            parse_gitlab($p)
          elif ($host|test("(^|\\.)bitbucket\\.[^/]+$")) then
            # Bitbucket Server (projects/<KEY>/repos/<slug>) 優先
            (parse_bitbucket_server($p) as $bb
            | if $bb.repo != "" then $bb else parse_default($p) end)
          else
            parse_default($p)
          end
      end
  '
  return 0
}

########################################
# 共通: 進捗表示
########################################
# 使い方: update_progress <done> <total>
# - 端末(TTY)のときは同じ行を上書き（\r と \033[K を使用）
# - 非TTY（ログ等）のときは毎回改行してもOK
function update_progress() {
  local done="$1"
  local total="$2"
  local progress_message="進捗: 取得済み/合計 ${done}/${total}"

  if [[ -t 2 ]]; then
    # \r: 行頭へ戻る, \033[K: カーソルから行末まで消去
    printf '\r\033[K%s' "$progress_message" >&2
  else
    printf '%s\n' "$progress_message" >&2
  fi
}

########################################
# 加工
########################################
function process_raw_data() {
  # $1: 依存関係の raw JSON
  local raw_file_path="$1"

  # 総件数を先に算出（実際のイテレーションと同じ jq で処理するため）
  local total_deps
  total_deps="$(
    jq -r '
      .dependencies // []
      | map({ platform, project_name })
      | map(select(.platform != null and .project_name != null))
      | sort_by(.platform, .project_name)
      | unique_by(.platform, .project_name)
      | length
    ' "$raw_file_path"
  )"

  # 進捗カウンタ初期化＆最初の表示（0/total）
  local done=0
  if ((total_deps > 0)); then
    update_progress "$done" "$total_deps"
  fi

  # 各オブジェクトを1行ずつ貯めるNDJSONファイル。一時ファイルに保存しないとjqの引数の最大量を超えてしまう
  local libs_ndjson
  libs_ndjson="$(mktemp)"
  trap 'rm -f -- "$libs_ndjson"' RETURN

  # 依存ライブラリの (platform, name) を抽出
  while IFS=$'\t' read -r platform project_name; do

    # 各依存について repository_urlのAPIで取得
    local repo_info
    repo_info="$(get_repo_info "$platform" "$project_name" || true)"

    if [[ -z "${repo_info:-}" ]]; then
      echo "skip: repo_info fetch failed ($platform $project_name)" >&2
      continue
    fi

    # repository_url / source_code_url など候補を順に採用（空でもOK：スキップしない）
    local repo_url
    local parsed

    repo_url="$(
      printf '%s' "$repo_info" | jq -r '
    # 空白をトリムし、「非空の文字列」だけを残す補助関数
    def nonempty: select(type=="string") | gsub("^\\s+|\\s+$"; "") | select(. != "");

    # 候補URLの優先順位リスト（上から順に採用）
    [
      .repository_url,
      .source_code_url,
      .github_repo_url,
      .security_policy_url,
      .code_of_conduct_url,
      .contribution_guidelines_url,
      .homepage
    ]
    | map(nonempty)        # 非空だけを残す
    | .[0] // ""           # 先頭（最初に見つかった非空）か、無ければ空文字
  '
    )"

    # URL がなければスキップ
    [[ -z "$repo_url" ]] && {
      echo "skip: no repo_url" >&2
      continue
    }

    parsed="$(parse_repo_url "$repo_url")"

    # 解析に失敗（empty）ならスキップ
    [[ -z "$parsed" ]] && {
      echo "skip: parse failed ($repo_url)" >&2
      continue
    }

    local repo_tmp combined
    repo_tmp="$(mktemp)"
    printf '%s' "$repo_info" >"$repo_tmp"

    combined="$(
      jq -cn \
        --argjson base "$parsed" \
        --slurpfile info "$repo_tmp" '
        # $info[0] が取得JSON（オブジェクト）
        ($info|length > 0 and ($info[0]|type=="object")) as $ok |
        (if $ok then $info[0] else {} end) as $info0 |
        {
          homepage: ($info0.homepage // ""),
          package_manager_url: ($info0.package_manager_url // ""),
          repository_url: ($info0.repository_url // $info0.source_code_url // $info0.github_repo_url // $info0.homepage // "")
        }
        | $base + .                              # 解析した host/owner/repo に追加
      '
    )"
    rm -f "$repo_tmp"

    # 1行1オブジェクトで追記（NDJSON）
    printf '%s\n' "$combined" >>"$libs_ndjson"

    # 反復の最初にカウント進めて表示を更新 ===
    ((done++))
    update_progress "$done" "$total_deps"

  done < <(
    jq -r '
      .dependencies // []
      | map({ platform, project_name })
      | map(select(.platform != null and .project_name != null))
      | sort_by(.platform, .project_name)
      | unique_by(.platform, .project_name)
      | .[]
      | [.platform, .project_name]
      | @tsv
    ' "$raw_file_path"
  )

  # === 追加: 進捗行を確定させるための改行（stderr） ===
  if ((total_deps > 0)); then
    printf '\n' >&2
  fi

  # Bash配列(各行が JSON オブジェクト) → jq --slurp(-s) で JSON 配列へ
  libs_json="$(
    jq -s '
      ( . // [] )
      | sort_by(.host // "", .owner // "", .repo // "", .repository_url // "")
      | unique_by(.host // "", .owner // "", .repo // "", .repository_url // "")
    ' "$libs_ndjson"
  )"

  # 最終 JSON を組み立て（--arg は文字列、--argjson は JSON 値を受け取る）
  formatted_output_json="$(
    jq -n \
      --arg createdAt "$(date +%Y-%m-%d)" \
      --arg owner "$OWNER" \
      --arg repo "$REPO" \
      --argjson libs "$libs_json" \
      '{
      meta: {
        createdAt: $createdAt,
        "specified-oss": { owner: $owner, repository: $repo }
      },
      data: { libraries: $libs }
    }'
  )"

  # 結果を返す
  printf '%s\n' "$formatted_output_json" | jq '.'
  return 0
}

########################################
# 保存
########################################
function save_output() {
  # $1: 出力 JSON
  local json="$1"
  local out_file
  out_file="${RESULTS_DIR}/${OWNER}-${REPO}-${SERVICE}/formatted-data/dependency_$(date +%Y%m%d_%H%M%S).json"
  echo "$json" | jq '.' >"$out_file"
  echo "Saved: $out_file" >&2
}

########################################
# 実行の流れを定義
########################################
function main() {
  # 出力ディレクトリの作成
  setup_output_directory

  # 1) 依存関係の raw を取得
  local raw_file_path
  raw_file_path=$(get_dependencies)

  # 2) README 形式に整形
  local output_json
  output_json=$(process_raw_data "$raw_file_path")

  # 3) 保存
  save_output "$output_json"

  return 0
}

########################################
# スクリプトを実行
########################################
main
