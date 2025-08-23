#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

readonly OWNER=${1:-"yoshiko-pg"}
readonly REPO=${2:-"difit"}
readonly RESULTS_DIR="./results"

function setup_output_directory() {
  # RESULTS_DIRディレクトリが存在しない場合は作成
  if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
  fi

  # REPOディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}"
  fi

  # raw-data/dependenciesディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/raw-data/dependencies" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/raw-data/dependencies"
  fi

  # raw-data/repo-infoディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/raw-data/repo-info" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/raw-data/repo-info"
  fi

  # formatted-dataディレクトリが存在しない場合は作成
  if [[ ! -d "${RESULTS_DIR}/${REPO}/formatted-data" ]]; then
    mkdir -p "${RESULTS_DIR}/${REPO}/formatted-data"
  fi

  return 0
}

function get_repo_info() {
  # $1: パッケージマネージャー名
  # $2: プロジェクト名

  # リポジトリ情報を取得
  local url
  url="https://libraries.io/api/${1}/$(echo -n "${2}" | jq -sRr '@uri')"

  # 出力PATHを作成
  local raw_file
  raw_file="${RESULTS_DIR}/${REPO}/raw-data/repo-info/${1}-${OWNER}-${REPO}-$(date +%Y%m%d_%H%M%S).json"

  # 取得結果をファイルへ保存しつつ内容を標準出力へ返す
  curl -sS "${url}" | tee "$raw_file" | jq '.'
  return 0
}

setup_output_directory
get_repo_info npm @types/prismjs
