# 「libraries.io」を使用する方法

## 概要

- 「libraries.io」の API からデータを取得して依存関係を出力する

## 使用方法

1. API キーを取得
   - [libraries.io](https://libraries.io/account)にログインして、「Settings」から API キーをコピー
2. API キーを環境変数として指定
   ```shell
   export LIBRARIES_IO_API_KEY=<APIキー>
   ```
3. 権限を付与
   ```shell
   chmod +x ./libraries.io/main.sh
   ```
4. 以下コマンドの実行
   ```shell
   ./libraries.io/main.sh <オーナー名> <リポジトリ名> <ホスティングサービス名>
   ```

## メモ

1. API の RateLimit の関係で、一つのリクエスト 1.2 秒間隔なので、依存関係が多いと時間がかかる
1. libraries.io で、dependency.json が取得できない時がある
   - libraries.io が全部のデータを取得していないっぽい

## 改善点

1. url が取得できなくても、スキップしたくない
   - dependency.json の記載は空欄でもよいから依存関係は把握したい。
