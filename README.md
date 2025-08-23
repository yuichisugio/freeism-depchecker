# freeism-depchecker

## 概要

- 引数で指定したライブラリが依存しているライブラリの一覧を出力するライブラリ

## ファイル構造

- 依存関係を出力するロジック別でフォルダ分けをしている
- 各ロジック直下に、以下がある
  1.  実行する`main.sh`
  1.  出力結果が入る`results`フォルダ
  1.  各ロジックごとの説明が記載されている`document.md`

## 種類

1. 「GitHub API」と「Google Open Source Insights」を組み合わせる方法

   - <a href="https://docs.github.com/ja/rest/dependency-graph/sboms" target="_blank" rel="noopener noreferrer">https://docs.github.com/ja/rest/dependency-graph/sboms</a>
   - <a href="https://github.com/google/deps.dev?tab=readme-ov-file#data" target="_blank" rel="noopener noreferrer">https://github.com/google/deps.dev?tab=readme-ov-file#data</a>

1. 「libraries.io」を使用する方法
   - <a href="https://libraries.io/api" target="_blank" rel="noopener noreferrer">https://libraries.io/api</a>

## 出力形式

- 2 つのファイル形式で出力する

1. raw データ
   - 返されたデータをそのまま記載
2. 以下の形式
   - `host`,`owner`,`repo`は必須
   - `package_manager_url`,`repository_url`,`homepage`は任意
   ```json
   {
   	"meta": {
   		"createdAt": "2025-08-20",
   		"specified-oss": {
   			"owner": "ryoppippi",
   			"Repository": "ccusage"
   		}
   	},
   	"data": {
   		"libraries": [
   			{
   				"host": "gitlab.com",
   				"owner": "group",
   				"repo": "lib-b"
   			},
   			{
   				"host": "github.com",
   				"owner": "acme",
   				"repo": "lib-a",
   				"package_manager_url":"pack-D",
   				"homepage":"page-p",
   				"repository_url":"git/e"
   			},
   			...
   		]
   	}
   }
   ```
