#!/bin/bash

# エラー時に停止
set -euo pipefail

# 相対PATHを安定させる。
cd "$(readlink -f "$(dirname -- "$0")")"

# 引数: OWNER / REPO
readonly OWNER=${1:-"ryoppippi"}
readonly REPO=${2:-"ccusage"}

# タイムスタンプ
readonly TS="$(date +%Y%m%d_%H%M%S)"
readonly TODAY="$(date +%F)"

# 出力ファイル名
readonly OUT_DIR="./results"
readonly RAW_SBOM_JSON="${OUT_DIR}/${OWNER}_${REPO}/raw_${TS}.json"
readonly PREP_JSON="${OUT_DIR}/${OWNER}_${REPO}/prep_${TS}.json"
readonly LIBS_JSON="${OUT_DIR}/${OWNER}_${REPO}/libs_${TS}.json"
readonly OUTPUT_JSON="${OUT_DIR}/${OWNER}_${REPO}/output_${TS}.json"

# 1) リポジトリの SBOM を取得（SPDX JSON）
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/${OWNER}/${REPO}/dependency-graph/sbom" |
  jq '.' \
    >"${RAW_SBOM_JSON}"

# 2) 直接依存（root → DEPENDS_ON）で npm の name / version / purl を整形
jq --indent 2 '
  .sbom as $s
  # root SPDXRef を特定
  | ($s.relationships[]
       | select(.relationshipType=="DESCRIBES" and .spdxElementId=="SPDXRef-DOCUMENT")
       | .relatedSpdxElement) as $root

  # SPDXID -> {name, version, purl} 辞書
  | ($s.packages
      | map({
          key: .SPDXID,
          value: {
            name: .name,
            version: (.versionInfo // ""),
            purl: ((.externalRefs[]? | select(.referenceType=="purl") | .referenceLocator) // "")
          }
        })
      | from_entries) as $pkg

  # 直接依存の SPDXID → 実体へ
  | [ $s.relationships[]
      | select(.relationshipType=="DEPENDS_ON" and .spdxElementId==$root)
      | .relatedSpdxElement
      | $pkg[.]
      | select(.purl != "") ] as $deps

  # version が空なら purl から補完（@version?… を抜く）
  | $deps
  | map(
      .version = (if (.version|length)>0 then .version
                  else (.purl | capture("@(?<v>[^?#]+)").v // "")
                  end)
    )
  # npm のみ
  | map(select(.purl | startswith("pkg:npm/")))

  # name が @scope/name のような形式でも OK。deps.dev のパス用に URL エンコードした name も持たせる
  | map(. + { name_enc: ( .name | @uri ) })

  # 出力
  | {
      meta: {
        createdAt: "'"${TODAY}"'",
        "specified-oss": { owner: "'"${OWNER}"'", Repository: "'"${REPO}"'" }
      },
      deps: .
    }
' "${RAW_SBOM_JSON}" >"${PREP_JSON}"

# 3) deps.dev GetVersion API を各依存に対して叩き、関連プロジェクト(= ソースリポジトリ)を抽出
#    参考: GET /v3/systems/npm/packages/{name}/versions/{version}
#    レスポンス: links[], relatedProjects[].projectKey.id (github.com/user/repo 等)
#    ※ 失敗しても処理継続（空配列扱い）
>"${LIBS_JSON}.tmp"

# 依存ごとの API URL を列挙（重複除去）
mapfile -t DEPS_URLS < <(
  jq -r '
    .deps[]
    | select((.name_enc|length)>0 and (.version|length)>0)
    | "https://api.deps.dev/v3/systems/npm/packages/\(.name_enc)/versions/\(.version)"
  ' "${PREP_JSON}" | sort -u
)

for url in "${DEPS_URLS[@]}"; do
  # -f で 4xx/5xx をエラーにする。失敗時は空 JSON を渡して継続。
  resp="$(curl -fsSL "${url}" 2>/dev/null || echo "{}")"

  # 1レスポンス → 複数リポジトリ（relatedProjects）を jsonl で出力
  echo "${resp}" | jq -c '
    def link_map:
      reduce (.links // [])[] as $l ({}; 
        . as $acc
        | ((($l.label // "") | ascii_downcase) ) as $lab
        | if ($lab | test("home")) then $acc + {homepage: $l.url}
          elif ($lab | test("repo|source")) then $acc + {repository_url: $l.url}
          elif ($lab | test("npm|package|registry")) then $acc + {package_manager_url: $l.url}
          else $acc end
      );

    def proj_list:
      [ (.relatedProjects // [])
        | .[]
        | select(.relationType == "SOURCE_REPO")
        | .projectKey.id  # e.g., "github.com/user/repo"
      ];

    # relatedProjects を優先、なければ links の repository_url から組み立て
    (link_map) as $links
    | (proj_list) as $ids
    | if ($ids|length) > 0 then
        $ids
        | map( split("/") | {host: .[0], owner: .[1], repo: (.[2] // "")} )
        | map(.repo |= sub("\\.git$"; ""))
        | map(. + $links)
      else
        # fallback: repository_url が GitHub/GitLab/Bitbucket のときだけ採用
        ( $links.repository_url // null ) as $ru
        | if $ru != null and ($ru | test("^https?://(github\\.com|gitlab\\.com|bitbucket\\.org)/")) then
            ( $ru | sub("^https?://"; "") | split("/") ) as $s
            | [ { host: $s[0], owner: $s[1], repo: ($s[2] // "") | sub("\\.git$"; "") } + $links ]
          else
            []
          end
      end
      | .[]
  ' >>"${LIBS_JSON}.tmp"
done

# 4) 重複除去して libraries 配列に整形
jq -s '
  # jsonl → 配列、host/owner/repo でユニーク
  unique_by(.host + "/" + .owner + "/" + .repo)
' "${LIBS_JSON}.tmp" >"${LIBS_JSON}"

# 5) 最終出力（ご指定フォーマット）
jq --arg createdAt "${TODAY}" \
  --arg owner "${OWNER}" \
  --arg repo "${REPO}" \
  --slurpfile libs "${LIBS_JSON}" \
  -n '
{
  meta: {
    createdAt: $createdAt,
    "specified-oss": { owner: $owner, Repository: $repo }
  },
  data: { libraries: $libs[0] }
}
' >"${OUTPUT_JSON}"

echo "Wrote ${OUTPUT_JSON}"
