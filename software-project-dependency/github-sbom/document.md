# github-sbom

## 概要

- GitHub Dependency Graph の SBOM API から依存情報を取得し、purl を用いた一覧に整形して出力します。
- `data[].owner` は持たず、`data[].repo` はネームスペース込み（例: `org/name`）。加えて `data[].purl` を含みます。
- purl は SPDX の externalRefs から抽出するため、言語やパッケージマネージャに依存せず扱いやすい形式です。

---

## 前提条件

- 環境: bash が動作する macOS / Linux
- 必須コマンド: `curl`, `jq`, `gh`（GitHub CLI, 認証必須）
- GitHub CLI の認証が完了していること
  - 例: `gh auth login` → `gh auth status` が成功すること

---

## UI: 使い方（Step by Step）

1. 実行権限を付与
   ```bash
   chmod +x ./github-sbom/main.sh
   ```
2. GitHub CLI を認証
   ```bash
   gh auth login
   gh auth status
   ```
3. 実行（引数は `OWNER REPO`）
   ```bash
   ./github-sbom/main.sh ryoppippi ccusage
   ```
4. オプション
   - ヘルプ: `./github-sbom/main.sh -h`
   - レートリミット表示: `./github-sbom/main.sh -r`

---

## 出力先

- `github-sbom/results/{OWNER}_{REPO}/raw-data/raw_*.json`（取得した SBOM の生データ）
- `github-sbom/results/{OWNER}_{REPO}/formatted-data/result_*.json`（整形済みの共通 JSON）

---

## ロジック: 処理の流れ

1. SBOM を取得

- GitHub REST API（Dependency Graph SBOM）を `gh api` で呼び出し、取得結果を `raw-data` に保存します。
- エンドポイント: `GET /repos/{owner}/{repo}/dependency-graph/sbom`

2. purl を抽出して整形

- `sbom.packages[].externalRefs[]` から `referenceType == "purl"` の `referenceLocator` を抽出
- purl から `host` と `repo`（ネームスペース+名前）を導出し、`host+repo` で一意化
- メタ情報（生成日時・指定 OSS）を付与して `formatted-data` に保存

---

## 出力スキーマ（例）

```json
{
	"meta": {
		"createdAt": "2025-08-20_12:34:56Z",
		"specified-oss": { "owner": "ryoppippi", "Repository": "ccusage" }
	},
	"data": [
		{ "host": "github.com", "repo": "acme/lib-a", "purl": "pkg:github/acme/lib-a@1.2.3" },
		{ "host": "gitlab.com", "repo": "group/lib-b", "purl": "pkg:gitlab/group/lib-b@0.9.0" }
	]
}
```

---

## オプション

- `-h, --help`: 使い方を表示
- `-r, --ratelimit`: 依存グラフ SBOM API のレートリミット（リセット時刻含む）を表示

---

## 注意点 / 制限

- リポジトリで Dependency graph が有効である必要があります。プライベート/内部リポジトリはトークンスコープに依存します。
- すべてのパッケージが purl を持つとは限りません。purl が無いパッケージは出力に含まれません。
- `owner` は出力されません。`repo` にネームスペース（`org/` など）を含みます。
- 同一 `host+repo` は重複除去されます。バージョン違いを区別したい場合は `purl` を参照してください。

---

## トラブルシューティング

- `gh auth status` が失敗する: `gh auth login` で再認証してください。
- 403/404 が返る: リポジトリで SBOM が有効化されていない、または権限不足の可能性があります。
- 出力が空: 該当バージョンに purl が存在しない、あるいは依存が検出されていない可能性があります。

---

## リンク

- GitHub Dependency Graph SBOM: `https://docs.github.com/ja/rest/dependency-graph/sboms`
- Package URL (purl) 仕様: `https://github.com/package-url/purl-spec`
- SPDX Spec: `https://spdx.github.io/spdx-spec/`

---

## メモ

- 結局、求めている形式は、依存ライブラリの一覧さえ手に入れば良いので、GitHub の URL など、少し処理が複雑化するのは一旦は不要
  - `README.md`に記載の出力形式とは違い、`owner`キーがないけど、一旦は大丈夫。
  - `README.md`に記載の出力形式を修正して、`owner`キーと`repo`キーのバラバラバージョンと合わせたバージョンを追加すれば良さそう？
