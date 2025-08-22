#!/bin/bash

# Libraries.io から依存関係を取得するファイル

########################################
# 設定
########################################

# エラー検知、パイプラインのエラー検知、未定義変数のエラー検知で、即時停止
set -euo pipefail

# スクリプトのディレクトリに移動。相対PATHを安定させる。
cd "$(dirname "$0")"

raw_json="$1"

# 依存ライブラリの (platform, name) を抽出
# 一部の platform/name は repository_url が無い場合があるため、その場合はスキップ
libs_tmp=$(mktemp)
trap 'rm -f "$libs_tmp"' EXIT
echo "$libs_tmp"

# # 依存の配列を反復処理
while IFS=$'\t' read -r platform project_name; do
  echo "start: $platform $project_name"
  echo "$platform $project_name"
  echo "end: $platform $project_name"
done <<< "$(echo "$raw_json" | jq -r '.dependencies // [] | .[] | "\(.platform)\t\(.project_name)"')"
