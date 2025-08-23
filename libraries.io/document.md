# 「libraries.io」を使用する方法

## 概要
- 「libraries.io」のAPIからデータを取得して依存関係を出力する

## 使用方法
1. APIキーを取得
    - [libraries.io](https://libraries.io/account)にログインして、「Settings」からAPIキーをコピー
2. APIキーを環境変数として指定
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
1. APIのRateLimitの関係で、一つのリクエスト1.2秒間隔なので、依存関係が多いと時間がかかる
