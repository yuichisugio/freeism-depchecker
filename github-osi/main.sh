#!/bin/bash

# GitHub Dependency Graph の SBOM を取得して、依存（パッケージ）単位で
# リポジトリ情報を解決し、formatted-data に “58件” をそのまま出力する版

set -euo pipefail

# 相対PATHを安定させる
cd "$(cd "$(dirname -- "$0")" && pwd -P)"

# 依存コマンドの確認
for cmd in curl gh jq sed awk tr; do
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

# 引数: OWNER / REPO
readonly OWNER=${1:-"ryoppippi"}
readonly REPO=${2:-"ccusage"}

# タイムスタンプ
# shellcheck disable=SC2155
readonly TS="$(date +%Y%m%d_%H%M%S)"
# shellcheck disable=SC2155
readonly TODAY="$(date +%F)"

# 出力ファイル
readonly RESULTS_DIR="./results/${OWNER}_${REPO}"
readonly RAW_SBOM_JSON="${RESULTS_DIR}/raw-data/raw_${TS}.json"
readonly PREP_JSON="${RESULTS_DIR}/raw-data/prep_${TS}.json"
readonly LIBS_JSON="${RESULTS_DIR}/raw-data/libs_${TS}.json"
readonly OUTPUT_JSON="${RESULTS_DIR}/formatted-data/output_${TS}.json"
readonly DEPS_JSONL="${RESULTS_DIR}/raw-data/deps_${TS}.jsonl"

show_usage() {
  cat <<EOF
Usage:
  $0 [OWNER] [REPO]

Description:
  「GitHubのDependency Graph」と「Open Source Insights(deps.dev)」および
  必要に応じて npm registry / JSR を用いて依存からソースリポジトリを解決します。

Options:
  -h, --help   ヘルプ
  -r, --ratelimit レートリミット表示
  -rm, --remove  results 直下のフォルダを対話選択して削除

Output:
  ${OUTPUT_JSON}  # formatted-data（依存=パッケージ単位：重複除去しない）

Examples:
  $0 ryoppippi ccusage
EOF
}

if [[ ("${1:-}" == "-h" || "${1:-}" == "--help") ]]; then
  show_usage
  exit 0
fi

########################################
# RateLimit
########################################
check_ratelimit() {
  gh api -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /rate_limit |
    jq '.resources.dependency_sbom
          | .reset |= (strftime("%Y-%m-%d %H:%M:%S UTC"))'
}
if [[ ("${1:-}" == "-r" || "${1:-}" == "--ratelimit") ]]; then
  check_ratelimit
  exit 0
fi

########################################
# Remove option
########################################
########################################
# results ディレクトリ配下フォルダの対話削除
# - 依存: fzf があれば矢印選択。無ければ番号選択にフォールバック
########################################
remove_results_directory() {
  local root_dir="./results"

  if [[ ! -d "$root_dir" ]]; then
    echo "ERROR: results フォルダが見つかりません: $root_dir" >&2
    exit 1
  fi

  # 直下のディレクトリ一覧を取得（フォルダ名のみ）
  local -a subdirs=()
  mapfile -t subdirs < <(find "$root_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)

  if [[ ${#subdirs[@]} -eq 0 ]]; then
    echo "ERROR: results 直下にフォルダがありません。" >&2
    exit 1
  fi

  local selected=""
  if command -v fzf >/dev/null 2>&1; then
    # fzf がある場合は矢印キーで選択
    selected="$(printf '%s\n' "${subdirs[@]}" | fzf --prompt='削除対象を選択: ' --height=40% --reverse || true)"
  else
    # fzf が無い場合は番号選択
    echo "fzf が見つからないため、番号選択にフォールバックします。" >&2
    local i=1 idx
    for d in "${subdirs[@]}"; do
      printf '%2d) %s\n' "$i" "$d"
      i=$((i + 1))
    done
    echo " 0) キャンセル"
    read -r -p "番号を選んでください: " idx
    if [[ ! "$idx" =~ ^[0-9]+$ || "$idx" -lt 0 || "$idx" -gt ${#subdirs[@]} ]]; then
      echo "キャンセルしました。" >&2
      exit 1
    fi
    if [[ "$idx" -eq 0 ]]; then
      echo "キャンセルしました。" >&2
      exit 0
    fi
    selected="${subdirs[$((idx - 1))]}"
  fi

  if [[ -z "$selected" ]]; then
    echo "キャンセルしました。" >&2
    exit 1
  fi

  local target="$root_dir/$selected"

  # 安全確認
  if [[ ! -d "$target" ]]; then
    echo "ERROR: ディレクトリではありません: $target" >&2
    exit 1
  fi

  printf '選択: %s\n' "$target"
  local ans
  read -r -p "本当に削除しますか? [y/N]: " ans
  case "$ans" in
  y | Y | yes | YES)
    rm -rf -- "$target"
    echo "削除しました: $target"
    ;;
  *)
    echo "キャンセルしました。"
    ;;
  esac
}

if [[ ("${1:-}" == "-rm" || "${1:-}" == "--remove") ]]; then
  remove_results_directory
  exit 0
fi

########################################
# URL 正規化（404対策）
# - git+https:// → https://
# - git://       → https://
# - git+ssh://git@github.com/OWNER/REPO → https://github.com/OWNER/REPO
# - 末尾 .git / #fragment を除去
########################################
normalize_repo_url() {
  local u="${1:-}"
  u="${u%% }"
  u="${u## }"
  u="${u#git+}"              # git+https:// → https://
  u="${u/git:\/\//https://}" # git:// → https://
  u="$(printf '%s' "$u" | sed -E 's|^git\+ssh://git@github\.com/|https://github.com/|I')"
  u="$(printf '%s' "$u" | sed -E 's|\.git(#.*)?$||I')" # .git, .git#frag
  u="$(printf '%s' "$u" | sed -E 's|#.*$||')"          # #fragment
  printf '%s' "$u"
}

########################################
# JSR リゾルバ（@jsr/scope__name → GitHub）
# https://jsr.io/@scope/name を読んで github.com/owner/repo を抽出
########################################
resolve_jsr_to_github() {
  local pkg="$1"               # 例: @jsr/std__async
  local scoped="${pkg#@jsr/}"  # std__async
  local scope="${scoped%%__*}" # std
  local name="${scoped#*__}"   # async
  local url="https://jsr.io/@${scope}/${name}"

  # 失敗しても空で返す（パイプラインを止めない）
  local html
  html="$(curl -fsSL "$url" 2>/dev/null || true)"
  # github.com/owner/repo を最初の1つだけ拾う
  local ghpath
  ghpath="$(printf '%s' "$html" | grep -Eo 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' | head -n1)"
  if [[ -n "$ghpath" ]]; then
    printf '%s\n' "$ghpath"
  fi
}

########################################
# 出力先ディレクトリ
########################################
setup_output_directory() {
  mkdir -p "${RESULTS_DIR}/raw-data" "${RESULTS_DIR}/formatted-data"
}

########################################
# SBOM → 依存抽出
########################################
get_sbom_and_prep() {
  # 1) SBOM 取得
  gh api -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/${OWNER}/${REPO}/dependency-graph/sbom" |
    jq '.' >"${RAW_SBOM_JSON}"

  # 2) root 直下 DEPENDS_ON を抽出し、purl 等を整形
  jq --indent 2 '
    .sbom as $s
    | ($s.relationships[] | select(.relationshipType=="DESCRIBES" and .spdxElementId=="SPDXRef-DOCUMENT") | .relatedSpdxElement) as $root

    | ($s.packages
        | map({
            key: .SPDXID,
            value: {
              name: .name,
              spdxid: .SPDXID,
              version: (.versionInfo // ""),
              purl: ((.externalRefs[]? | select(.referenceType=="purl") | .referenceLocator) // "")
            }
          })
        | from_entries) as $pkg

    | [ $s.relationships[]
        | select(.relationshipType=="DEPENDS_ON" and .spdxElementId==$root)
        | .relatedSpdxElement
        | $pkg[.]
        | select(.purl != "") ] as $deps

    | $deps
    | map(
        def strip_range:
          gsub("^%5[Ee]";"") | gsub("^\\^";"") |
          gsub("^%7[Ee]";"") | gsub("^~";"")   |
          gsub("^%3[Ee]%3[Dd]";"") | gsub("^%3[Cc]%3[Dd]";"") |
          gsub("^%3[Ee]";"") | gsub("^%3[Cc]";"");

        (try (.purl | capture("^pkg:(?<type>[^/]+)/(?<path>[^@?#]+)(?:@(?<ver>[^?#]+))?")) catch null) as $p
        | select($p != null)

        | .version_exact =
            ( if ($p.ver // "" | length) > 0 then ($p.ver|strip_range)
              elif ((.version // "" ) | length) > 0 then ((.version|strip_range))
              else
                (.spdxid // "" | sub("-[0-9a-f]{4,}$"; "") | match("[0-9][0-9A-Za-z\\.-]*[0-9A-Za-z]")? | if .==null then "" else .string end)
              end )

        | .system = ({ npm:"NPM", maven:"MAVEN", pypi:"PYPI", golang:"GO", cargo:"CARGO", nuget:"NUGET", gem:"RUBYGEMS" }[$p.type] // null)
        | .system_supported = (.system != null)

        | .name_sys =
            (if .system=="MAVEN" then ($p.path | split("/") | [.[0], (.[1] // "")] | join(":"))
             elif .system=="NPM" then ( if ($p.path | startswith("%40")) then ($p.path | sub("^%40"; "@")) else .name end )
             else $p.path end)

        | .name_enc = (if (.name_sys|type)=="string" then (.name_sys|@uri) else null end)
        | .system_lc = (if .system != null then (.system|ascii_downcase) else null end)
        | .purl_type = ($p.type|ascii_downcase)
        | .purl_path = $p.path
      )
    | {
        meta: { createdAt: "'"${TODAY}"'", "specified-oss": { owner: "'"${OWNER}"'", Repository: "'"${REPO}"'" } },
        deps: .
      }
  ' "${RAW_SBOM_JSON}" >"${PREP_JSON}"

  # 3) 依存（1行=1依存）にして JSONL へ
  jq -c '.deps[]' "${PREP_JSON}" >"${DEPS_JSONL}"
}

########################################
# 依存 → リポジトリ解決（依存ごと=58件を出す）
########################################
resolve_repos_per_dep() {
  : >"${LIBS_JSON}.tmp"

  while IFS= read -r dep; do
    name="$(jq -r '.name' <<<"$dep")"
    version_exact="$(jq -r '.version_exact' <<<"$dep")"
    purl_type="$(jq -r '.purl_type' <<<"$dep")"
    purl_path="$(jq -r '.purl_path' <<<"$dep")"
    system_supported="$(jq -r '.system_supported' <<<"$dep")"
    system_lc="$(jq -r '.system_lc // empty' <<<"$dep")"
    name_enc="$(jq -r '.name_enc // empty' <<<"$dep")"

    host=""
    owner=""
    repo=""
    homepage=""
    repo_url=""

    # A) purl が github / githubactions のときは機械的に owner/repo を抽出
    if [[ "$purl_type" == "github" || "$purl_type" == "githubactions" ]]; then
      owner="$(printf '%s' "$purl_path" | awk -F/ '{print $1}')"
      repo="$(printf '%s' "$purl_path" | awk -F/ '{print $2}')"
      if [[ -n "$owner" && -n "$repo" ]]; then
        host="github.com"
        homepage="https://github.com/${owner}/${repo}"
        repo_url="$homepage"
      fi
    fi

    # B) 未解決なら deps.dev（v3）で SOURCE_REPO / links を引く
    if [[ -z "$host" && "$system_supported" == "true" && -n "$system_lc" && -n "$name_enc" && -n "$version_exact" ]]; then
      api_url="https://api.deps.dev/v3/systems/${system_lc}/packages/${name_enc}/versions/${version_exact}"
      resp="$(curl -fsSL "$api_url" 2>/dev/null || echo '{}')"

      # github を最優先で1件拾う。なければ links.repository_url から fallback。
      local -a cand=()
      readarray -t cand < <(printf '%s' "$resp" | jq -r '
        def link_map:
          reduce (.links // [])[] as $l ({}; . as $acc
            | ((($l.label // "") | ascii_downcase)) as $lab
            | if ($lab|test("home")) then $acc + {homepage: $l.url}
              elif ($lab|test("repo|source")) then $acc + {repository_url: $l.url}
              elif ($lab|test("npm|package|registry")) then $acc + {package_manager_url: $l.url}
              else $acc end);
        def proj_list:
          [ (.relatedProjects // [])[] | select(.relationType=="SOURCE_REPO") | .projectKey.id ];

        (link_map) as $links
        | (proj_list) as $ids
        | if ($ids|length) > 0 then
            $ids | map( split("/") | {host: .[0], owner: .[1], repo: (.[2] // "")} )
                | map(.repo |= sub("\\.git$"; "")) | .[]
          else
            ( $links.repository_url // empty ) as $ru
            | if $ru != "" and ($ru|test("^https?://(github\\.com|gitlab\\.com|bitbucket\\.org)/")) then
                ($ru | sub("^https?://"; "") | split("/") ) as $s
                | { host: $s[0], owner: $s[1], repo: ($s[2] // "") | sub("\\.git$"; "") }
              else empty end
          end
          | @json
      ')
      # github を優先選択
      for c in "${cand[@]}"; do
        hh="$(jq -r '.host' <<<"$c")"
        if [[ "$hh" == "github.com" ]]; then
          host="$hh"
          owner="$(jq -r '.owner' <<<"$c")"
          repo="$(jq -r '.repo' <<<"$c")"
          # links から URL を拾って正規化
          homepage="$(printf '%s' "$resp" | jq -r '[.links[]? | select((.label|ascii_downcase)|test("home")) | .url][0] // empty')"
          repo_url="$(printf '%s' "$resp" | jq -r '[.links[]? | select((.label|ascii_downcase)|test("repo|source")) | .url][0] // empty')"
          break
        fi
      done
      # github が無ければ最初の候補でも可
      if [[ -z "$host" && ${#cand[@]} -gt 0 ]]; then
        c="${cand[0]}"
        host="$(jq -r '.host' <<<"$c")"
        owner="$(jq -r '.owner' <<<"$c")"
        repo="$(jq -r '.repo' <<<"$c")"
        homepage="$(printf '%s' "$resp" | jq -r '[.links[]? | select((.label|ascii_downcase)|test("home")) | .url][0] // empty')"
        repo_url="$(printf '%s' "$resp" | jq -r '[.links[]? | select((.label|ascii_downcase)|test("repo|source")) | .url][0] // empty')"
      fi
    fi

    # C) まだ未解決で npm（NPM のみ）なら registry から repository.url / homepage を見る
    if [[ -z "$host" && "$system_lc" == "npm" && -n "$name_enc" ]]; then
      reg_json="$(curl -fsSL "https://registry.npmjs.org/${name_enc}" 2>/dev/null || echo '{}')"
      repo_url="$(printf '%s' "$reg_json" | jq -r '.repository.url // empty')"
      homepage="$(printf '%s' "$reg_json" | jq -r '.homepage // empty')"
      repo_url="$(normalize_repo_url "$repo_url")"
      homepage="$(normalize_repo_url "$homepage")"
      if [[ "$repo_url" =~ ^https?://github\.com/([^/]+)/([^/?#]+) ]]; then
        host="github.com"
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
      fi
    fi

    # D) さらに未解決で @jsr/… の場合は JSR ページから GitHub を抽出
    if [[ -z "$host" && "$system_lc" == "npm" && "$name" == @jsr/* ]]; then
      ghpath="$(resolve_jsr_to_github "$name" || true)"
      if [[ -n "$ghpath" && "$ghpath" =~ github\.com/([^/]+)/([^/?#]+) ]]; then
        host="github.com"
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        homepage="https://github.com/${owner}/${repo}"
        repo_url="$homepage"
      fi
    fi

    # URL 正規化
    homepage="$(normalize_repo_url "$homepage")"
    repo_url="$(normalize_repo_url "$repo_url")"

    # ここまでで host/owner/repo が無ければ空行としても“依存1件”は出力（件数維持）
    jq -n --arg host "$host" --arg owner "$owner" --arg repo "$repo" \
      --arg homepage "$homepage" --arg repository_url "$repo_url" \
      --arg pkg "$name" --arg ver "$version_exact" '
      {
        # 依存（パッケージ）単位で出力：識別用に package と version も含める
        package: { name: $pkg, version_exact: $ver },
        host: $host, owner: $owner, repo: $repo,
        homepage: $homepage, repository_url: $repository_url
      }
    ' >>"${LIBS_JSON}.tmp"

  done <"${DEPS_JSONL}"

  # “重複除去しない”で 58件をそのまま配列化（== 期待件数に一致）
  jq -s '.' "${LIBS_JSON}.tmp" >"${LIBS_JSON}"
}

########################################
# 最終出力
########################################
emit_output() {
  jq --arg createdAt "${TODAY}" \
    --arg owner "${OWNER}" \
    --arg repo "${REPO}" \
    --slurpfile libs "${LIBS_JSON}" \
    -n '
      {
        meta: { createdAt: $createdAt, "specified-oss": { owner: $owner, Repository: $repo } },
        data: { libraries: $libs[0] }  # ← 依存（パッケージ）単位：重複除去なし
      }' >"${OUTPUT_JSON}"

  printf 'Wrote %s\n' "${OUTPUT_JSON}" >&2
}

main() {
  setup_output_directory
  get_sbom_and_prep
  resolve_repos_per_dep
  emit_output
}

main
