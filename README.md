# freeism-depchecker

## 仕様

- GitHub CLI で、GitHub dependency graph の SBOM を取得
    - <a href="https://docs.github.com/ja/rest/dependency-graph/sboms" target="_blank" rel="noopener noreferrer">https://docs.github.com/ja/rest/dependency-graph/sboms</a>

## 出力形式
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
