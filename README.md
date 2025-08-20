# freeism-depchecker

## 概要

- 引数で指定したライブラリが依存しているライブラリの一覧を出力するライブラリ

## ファイル構造

- 依存関係を出力するロジック別でフォルダ分けをしている
- 各ロジック直下に、以下がある
	1. 実行する`main.sh`
	1. 出力結果が入る`results`フォルダ
	1. 各ロジックごとの説明が記載されている`document.md`

## 種類

1. GitHub API から、GitHub CLI を使用して、指定ライブラリの SBOM を取得する方法
   - <a href="https://docs.github.com/ja/rest/dependency-graph/sboms" target="_blank" rel="noopener noreferrer">https://docs.github.com/ja/rest/dependency-graph/sboms</a>
1. Google Open Source Insights からデータを取得する方法
   - <a href="https://deps.dev/" target="_blank" rel="noopener noreferrer">https://deps.dev/</a>

## 出力形式
- 2つのファイル形式で出力する

1. rawデータ
	- 返されたデータをそのまま記載
2. 以下の形式
	```json
	{
		"meta": {
			"createdAt": "2025-08-20",
			"destinated-oss": {
				"owner": "ryoppippi",
				"Repository": "ccusage"
			}
		},
		"data": {
			"libraries": ["a", "b", "c", "d"]
		}
	}
	```
