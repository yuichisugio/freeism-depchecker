# 「libraries.io」を使用する方法

## 概要

- Libraries.io の API を用いて依存関係と関連リポジトリ URL を取得し、共通 JSON 形式で出力します。
- 依存の重複をホスト/オーナー/リポジトリ/URL 単位でまとめてユニーク化します。

## 前提条件

- 必須コマンド: `curl`, `jq`
- API キーの用意（どちらかの環境変数名で設定可能）
  - `LIBRARIES_IO_API_KEY` または `LIBRARIES_API_KEY`

## UI: 使い方（Step by Step）

1. API キーを取得
   - [libraries.io](https://libraries.io/account)にログインして、「Settings」から API キーをコピー
2. API キーを環境変数として指定
   ```shell
   export LIBRARIES_IO_API_KEY=<APIキー>
   ```
3. 実行権限を付与
   ```shell
   chmod +x ./libraries.io/main.sh
   ```
4. 以下コマンドの実行
   ```shell
   ./libraries.io/main.sh <オーナー名> <リポジトリ名> <ホスティングサービス名>
   ```
   - 例
     ```bash
     ./libraries.io/main.sh yoshiko-pg difit github
     ```

## オプション / 実行時の挙動

- レートリミット対策
  - 環境変数 `RATE_LIMIT_DELAY`（秒, 既定 1.2）で連続呼び出し間隔を調整
  - HTTP 429/503 は指数バックオフ＋ジッタで自動リトライ（最大 5 回）
- 保存場所
  - raw 依存: `libraries.io/results/<OWNER>-<REPO>-<SERVICE>/raw-data/dependencies/*.json`
  - raw リポジトリ情報: `.../raw-data/repo-info/*.json`
  - formatted: `.../formatted-data/dependency_*.json`

## ロジック: 処理の流れ（内部仕様）

1. 出力先の初期化

   - `results/<OWNER>-<REPO>-<SERVICE>/{raw-data/{dependencies,repo-info},formatted-data}` を作成

2. 依存リストの取得（Libraries.io）

   - エンドポイント: `/{SERVICE}/{OWNER}/{REPO}/dependencies`
   - 取得 JSON を `raw-data/dependencies/*.json` に保存

3. 各依存のリポジトリ情報取得

   - `platform` と `project_name` ごとに `/{platform}/{project}` を呼び出し
   - 候補 URL の優先順位で `repository_url` を選択
   - `repository_url` → `source_code_url` → `github_repo_url` → `security_policy_url` → `code_of_conduct_url` → `contribution_guidelines_url` → `homepage`

4. URL の分解と整形

   - SSH/HTTP/HTTPS/API 形式を正規化して `{host, owner, repo}` に分解
   - GitHub API URL（`api.github.com/repos/:owner/:repo`）は `github.com` に正規化

5. ユニーク化とソート

   - `host`, `owner`, `repo`, `repository_url` をキーにユニーク化
   - 安定した順序になるようにソート

6. 出力組み立て

   - 共通スキーマで `meta` と `data.libraries` を出力

## メモ

1. API の RateLimit により、依存数が多いと時間がかかります（`RATE_LIMIT_DELAY` で調整可）

## この方法のデメリット

1. libraries.io で、dependency.json が取得できない時がある
   - libraries.io が様々な API やスクレイピングでデータ取得しているか否かに依存しているので、依存関係のデータが足りない場合がある
   - 全部のデータを取得していないっぽい
   - ほかの方法と一緒に実行して、統合するために使用するのが良さそう
