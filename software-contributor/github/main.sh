#!/bin/bash

# GitHub の OSS のコントリビューターを取得する

### 実行
set -euo pipefail

# 相対PATHを安定させる
cd "$(cd "$(dirname -- "$0")" && pwd -P)"
