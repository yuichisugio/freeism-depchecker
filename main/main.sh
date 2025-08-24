#!/bin/bash

# 各調査方法をすべて直列で起動して、その結果を取得して、重複削除して、統合した結果を出力する

########################################
# 実行するmain.shのパスの配列
########################################
readonly execute_file_path=("github-osi" "libraries.io")

########################################
# 準備
########################################
readonly OWNER="${1}"
readonly REPO="${2}"
readonly RESULTS_DIR="./results/${OWNER}_${REPO}"

### 実行
set -euo pipefail

# 相対PATHを安定させる
cd "$(cd "$(dirname -- "$0")" && pwd -P)"

# 実行するmain.shのパスを繰り返し実行
for file in "${execute_file_path[@]}"; do
  echo "実行: ${file}"
  ./"${file}"/main.sh "${1}" "${2}" "${3}"
  "${file}/results_${OWNER}_${REPO}"
done
