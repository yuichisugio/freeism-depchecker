# 「GitHub API」と「Google Open Source Insights」を組み合わせる方法

## 概要

- GitHub Dependency Graph の SBOM と Google Open Source Insights (deps.dev) を併用して、依存（パッケージ）ごとのリポジトリ URL を解決します。
- 依存単位で出力（重複除去なし）。formatted 出力の件数は SBOM の依存件数と一致します。
- 参考:
  - <a href="https://docs.github.com/ja/rest/dependency-graph/sboms" target="_blank" rel="noopener noreferrer">GitHub SBOM API</a>
  - <a href="https://github.com/google/deps.dev?tab=readme-ov-file#data" target="_blank" rel="noopener noreferrer">deps.dev Data</a>

## 前提条件（依存コマンド・認証）

- 必須コマンド: `curl`, `gh`（GitHub CLI）, `jq`, `sed`, `awk`, `tr`
- 任意コマンド: `fzf`（結果フォルダの対話削除で使用）
- GitHub CLI の認証が必要です。
  ```bash
  gh auth login
  gh auth status
  ```

## UI: 使い方（Step by Step）

1. 実行権限の付与（未実施の場合）
   ```bash
   chmod +x ./github-osi/main.sh
   ```
2. レートリミットを確認（任意）
   ```bash
   ./github-osi/main.sh --ratelimit
   ```
3. 実行
   ```bash
   ./github-osi/main.sh <OWNER> <REPO>
   # 例
   ./github-osi/main.sh ryoppippi ccusage
   ```
4. 出力の確認
   - raw: `github-osi/results/<OWNER>_<REPO>/raw-data/`
   - formatted: `github-osi/results/<OWNER>_<REPO>/formatted-data/output_*.json`

### オプション

- `-h, --help`: ヘルプを表示
- `-r, --ratelimit`: GitHub API のレートリミットを表示
- `-rm, --remove`: `results/` 直下のフォルダを対話選択で削除（`fzf` があれば矢印選択、無ければ番号選択）

## ロジック: 処理の流れ（内部仕様）

1. 出力先の初期化

   - `results/<OWNER>_<REPO>/{raw-data,formatted-data}` を作成

2. SBOM の取得（GitHub API）

   - エンドポイント: `/repos/:owner/:repo/dependency-graph/sbom`
   - 取得 JSON を `${RAW_SBOM_JSON}` に保存

3. 依存抽出（root 直下の DEPENDS_ON のみ）

   - `SPDX` の `relationships` から `root` → `DEPENDS_ON` → `packages` を引き、以下を整備
     - `system`（npm, maven, pypi, go, cargo, nuget, gem など）
     - `name_sys`（Maven は `groupId:artifactId`、npm はスコープ `%40` → `@` など）
     - `version_exact`（`^`, `~`, `>=`, `<=` 等を除去した確定版。無ければ `SPDXID` から推定）
   - 依存 1 件を 1 行にした JSONL を `${DEPS_JSONL}` へ

4. リポジトリ解決（依存 → {host, owner, repo}）

   - 依存ごとに次の順で解決します。
     - A: purl が `github` または `githubactions` の場合
       - `purl_path` を `owner/repo` として採用
     - B: 未解決なら deps.dev v3 を照会（`systems/{system}/packages/{name}/versions/{version}`）
       - `relatedProjects` の `SOURCE_REPO` を優先。`github.com` があれば最優先
       - 無ければ `links.repository_url` などから推定
       - `links` から `homepage` / `repository_url` も補完
     - C: さらに未解決で npm の場合
       - npm registry の `repository.url` / `homepage` を利用
     - D: さらに未解決で npm かつ `@jsr/...` の場合
       - `https://jsr.io/@scope/name` のページから `github.com/owner/repo` を抽出

5. URL 正規化

   - `git+https://` → `https://`、`git://` → `https://`、`git@github.com:` → `https://github.com/`
   - 末尾 `.git` と `#fragment` を除去

6. 出力組み立て

   - 依存（パッケージ）単位に、以下を配列で出力（重複除去なし）
     - `package.name`, `package.version_exact`
     - `host`, `owner`, `repo`, `homepage`, `repository_url`
   - ラッパー JSON
     - `meta.createdAt`、`meta.specified-oss`（`owner`, `Repository`）
     - `data.libraries` に配列を格納

## メモ

### サポートするパッケージマネージャ

- deps.dev v3 が対応するエコシステムを利用（npm, maven, pypi, go, cargo, nuget, gem など）

### 制限事項 / 注意点

- SBOM の root 直下の依存のみを対象（間接依存の判別は別途処理が必要）
- formatted 出力は重複除去なし（SBOM の依存件数と一致させるため）
- GitHub CLI の認証が無い場合はエラーになります

### 関連リンク

- GitHub SBOM API: `https://docs.github.com/ja/rest/dependency-graph/sboms`
- deps.dev Data: `https://github.com/google/deps.dev?tab=readme-ov-file#data`

### 補足

- jsr パッケージは、`jsr.io` から GitHub リンクを抽出して解決します。
