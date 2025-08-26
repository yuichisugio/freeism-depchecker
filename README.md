# freeism-depchecker

## 概要

- 指定した OSS リポジトリが依存しているライブラリ群を取得し、共通 JSON 形式で出力します。
- 取得方式は 2 種類（切り替え可能）。共通の使い方は本書、各方式の詳細は各 `document.md` を参照してください。

## ファイル構造

- 取得方式ごとにフォルダ分割
- 各方式ディレクトリ直下に配置
  1. 実行する `main.sh`
  2. 出力結果が入る `results/`
  3. 方式ごとの説明 `document.md`

```
freeism-depchecker/
  ├─ github-osi/
  │   ├─ main.sh
  │   ├─ results/
  │   └─ document.md
  └─ libraries.io/
      ├─ main.sh
      ├─ results/
      └─ document.md
```

## 方式（どちらかを選択）

- GitHub API + Google Open Source Insights(deps.dev)
  - `github-osi/main.sh`
  - GitHub SBOM API と deps.dev を組み合わせて解決
- Libraries.io API
  - `libraries.io/main.sh`
  - Libraries.io の API から依存とリポジトリ情報を収集

## 共通の前提条件

- bash が動作する環境（macOS / Linux）
- 以下のコマンドが利用可能であること
  - 必須: `curl`, `jq`
  - 方式別に追加要件あり（詳細は各 `document.md`）
    - GitHub + deps.dev 方式: `gh`（GitHub CLI, 認証必須）, `sed`, `awk`, `tr`（URL 正規化で使用）, `fzf` は任意（結果削除 UI）
    - Libraries.io 方式: 環境変数に API キーを設定（`LIBRARIES_IO_API_KEY` または `LIBRARIES_API_KEY`）

## セットアップ（共通）

1. 実行権限を付与
   ```bash
   chmod +x ./github-osi/main.sh
   chmod +x ./libraries.io/main.sh
   ```
2. 方式別の前提条件を満たす
   - GitHub CLI 認証や API キー設定など。詳細は各 `document.md` を参照。

## UI: 共通の使い方（Step by Step）

1. 方式を選ぶ（`github-osi` か `libraries.io`）
2. 引数を決める
   - GitHub + deps.dev 方式: `OWNER REPO`
   - Libraries.io 方式: `OWNER REPO SERVICE`（`github|gitlab|bitbucket`）
3. 実行例
   - GitHub + deps.dev 方式
     ```bash
     ./github-osi/main.sh ryoppippi ccusage
     ```
   - Libraries.io 方式
     ```bash
     ./libraries.io/main.sh yoshiko-pg difit github
     ```
4. 完了メッセージのパスに出力（詳細は下記「出力先」）

より詳しいオプションや注意点は各 `document.md` を参照してください。

## ロジック: 共通の出力仕様

- 2 種類のファイルを出力

  - raw データ: 取得元 API の生データ
  - formatted データ: 共通スキーマの JSON

- 共通 JSON スキーマ（例）
  - `host`,`owner`,`repo` は必須
  - `package_manager_url`,`repository_url`,`homepage` は任意
  ```json
  {
  	"meta": {
  		"createdAt": "2025-08-20",
  		"specified-oss": {
  			"owner": "ryoppippi",
  			"Repository": "ccusage"
  		}
  	},
  	"data": [
  		{
  			"host": "gitlab.com",
  			"owner": "group",
  			"repo": "lib-b"
  		},
  		{
  			"host": "github.com",
  			"owner": "acme",
  			"repo": "lib-a",
  			"package_manager_url": "pack-D",
  			"homepage": "page-p",
  			"repository_url": "git/e"
  		}
  	]
  }
  ```

## 出力先

- GitHub + deps.dev 方式
  - `github-osi/results/{OWNER}_{REPO}/raw-data/*.json`
  - `github-osi/results/{OWNER}_{REPO}/formatted-data/output_*.json`
- Libraries.io 方式
  - `libraries.io/results/{OWNER}-{REPO}-{SERVICE}/raw-data/**/*.json`
  - `libraries.io/results/{OWNER}-{REPO}-{SERVICE}/formatted-data/dependency_*.json`

## リンク

- GitHub Dependency Graph SBOM: `https://docs.github.com/ja/rest/dependency-graph/sboms`
- Google Open Source Insights(deps.dev): `https://github.com/google/deps.dev?tab=readme-ov-file#data`
- Libraries.io API: `https://libraries.io/api`
