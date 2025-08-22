# 「GitHub API」と「Google Open Source Insights」を組み合わせる方法

## 概要

- Google Open Source Insights
  - <a href="https://deps.dev/" target="_blank" rel="noopener noreferrer">https://deps.dev/</a>
- GitHub CLI で、GitHub dependency graph の SBOM を取得
  - <a href="https://docs.github.com/ja/rest/dependency-graph/sboms" target="_blank" rel="noopener noreferrer">https://docs.github.com/ja/rest/dependency-graph/sboms</a>

## サポートするパッケージマネージャ

- 参考
  - <a href="https://github.com/google/deps.dev?tab=readme-ov-file#data" target="_blank" rel="noopener noreferrer">https://github.com/google/deps.dev?tab=readme-ov-file#data</a>

## 取得ロジック

1. GitHub API から、GitHub CLI を使用して、引数で指定したライブラリの SBOM を取得する
1. 取得した情報を使用して、パッケージ名、リポジトリ名を抽出する
1. Open Source Insights からデータを取得する方法

## デメリット

1. 直接的な依存・間接的な依存を判別するのが面倒

## メモ

1. Google Open Source Insights からデータを取得する方法
