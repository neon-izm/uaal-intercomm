# uaal-intercomm

Unity 6000.3.10f1 の車ビューアを、Unity as a Library としてネイティブクライアントアプリ（ iOS/ Android )に渡すリポジトリです。  
サンプルのiOS/AndroidアプリはUnityを知らないままでビルドできます。  
車のモデルはRuntimeのUnityに入っておらず、起動後に Cloudflare R2 から Addressables でダウンロードします。

## ディレクトリ

| パス | 中身 |
| --- | --- |
| `uaal-intercomm/` | Unity プロジェクト。URP、Addressables 4.1.2 |
| `ios/UaalIntercomm/` | Swift Package。`UnityHost` と SwiftUI の `UnityView`。フレームワーク本体は R2 の zip |
| `ios-app/` | 確認用の SwiftUI アプリ。XcodeGen の `project.yml` |
| `android/uaal-intercomm/` | Kotlin の `UnityHost` と Compose の `UnityView` |
| `android-app/` | 確認用の Compose アプリ。上のモジュールを `projectDir` で含む |
| `scripts/` | R2 へのアップロードと、iOS の xcframework 作成 |


## 配布

公開 URL は `scripts/hosting.env` の `R2_PUBLIC_BASE` です。現在は次の r2.dev です。レート制限のある開発用エンドポイントです。

```text
https://pub-9480de868c60413c80b39cefa6089251.r2.dev
```

バケット名は `uaal-intercomm`。コンテンツの版は `1.0.0`。

```text
ios/1.0.0/UnityFramework.xcframework.zip
android/maven/dev/uaal/intercomm/unity-player/1.0.0/unity-player-1.0.0.aar
android/maven/dev/uaal/intercomm/unity-player/1.0.0/unity-player-1.0.0.pom
android/maven/dev/uaal/intercomm/unity-player/maven-metadata.xml
content/1.0.0/iOS/
content/1.0.0/Android/
```

Addressables の `Remote.LoadPath` はプレイヤーに焼き込んであります。

```text
https://pub-9480de868c60413c80b39cefa6089251.r2.dev/content/1.0.0/[BuildTarget]
```

iOS の Swift Package はリポジトリ内のソースです。`Package.swift` の `binaryTarget` が上の zip を checksum 付きで取得します。zip を作り直したら、`swift package compute-checksum` の値で checksum を更新します。

Android の Maven リポジトリは次です。

```text
https://pub-9480de868c60413c80b39cefa6089251.r2.dev/android/maven
```

`dev.uaal.intercomm:unity-player:1.0.0` です。この AAR は Unity のランタイム（Java、arm64 の jni、assets）です。Kotlin の `UnityHost` と Compose の `UnityView` は AAR に入っておらず、`android/uaal-intercomm` モジュールがこの座標を `api` で参照します。ABI は arm64-v8a だけです。

## ホスト API

iOS は `UnityHost.shared`、Android は `UnityHost.shared` です。呼び出しはそれぞれの UI スレッドです。

| 操作 | 意味 |
| --- | --- |
| `initialize` | ランタイムを起動し、`ready` を待つ。プロセス内で 1 回。iOS は引数なし。Android は `ComponentActivity` |
| `load` | `main` を Additive で載せる |
| `loadPrefab` | `carA` / `carB` / `carC` を取得して `Anchor` の子にする |
| `setColor(r, g, b)` | 出ている車の URP `_BaseColor` を 0 から 1 で塗る |
| `setCamera(1 \| 2 \| 3)` | 正面、側面、上面 |
| `keepOffscreen` | 描画面を外して pause する。プレイヤーは破棄しない |

終了 API はありません。描画面はプロセス内に 1 つです。

ネイティブから Unity へは、GameObject `Bridge` の `OnCommand` に JSON を渡します。Unity からネイティブへは、iOS が C 関数 `OnBridgeEvent`、Android が `dev.uaal.intercomm.UnityCallbacks.onBridgeEvent` です。

```json
{"op":"load"}
{"op":"loadPrefab","id":"carA"}
{"op":"setColor","r":1,"g":0,"b":0}
{"op":"setCamera","index":2}
```

```json
{"event":"ready"}
{"event":"loaded"}
{"event":"prefabLoaded","id":"carA"}
{"event":"error","op":"loadPrefab","message":"..."}
```

## サンプル

どちらも、最初の画面で Unity を隠したまま `initialize` と `load` をし、`車を見る` でスクロールできる画面に描画面を出します。

iOS は実機と arm64 シミュレータです。XcodeGen でプロジェクトを作ります。パッケージ解決時に R2 から xcframework を落とします。

```shell
cd ios-app
xcodegen generate
open UaalIntercommApp.xcodeproj
```

バンドル ID は `dev.uaal.intercomm.app`、deployment target は iOS 15 です。シミュレータは AppleSiliconで動作確認済み。

Android は JDK 17、Gradle 8.11.1、compileSdk 36、minSdk 25 です。`local.properties` に `sdk.dir` を書くか、`ANDROID_HOME` を設定します。

```shell
cd android-app
./gradlew :app:assembleDebug
```

`applicationId` は `dev.uaal.intercomm.app` です。arm64 のシステムイメージで動かします。

## Unityライブラリを出し直す

資格情報はリポジトリ直下の `.env` です。gitignore 済みで、`KEY=VALUE` ではありません。

```text
account id:<Cloudflare account id>
api token:<API token>
access key:<R2 access key>
secret access key:<R2 secret>
```

`scripts/publish-r2.sh` がこれを読み、値は表示しません。公開先と版は `scripts/hosting.env` です。

iOS は、このプロジェクトを開いている Unity エディタに対して `scripts/build-xcframework.sh` を実行します。実機と arm64 シミュレータの xcframework を `build/ios/` に作り、`content/1.0.0/iOS` と zip を R2 に上げ、checksum を表示します。表示された checksum を `ios/UaalIntercomm/Package.swift` に書きます。

Android の書き出しは、同じエディタで `UaalIntercomm.Editor.AndroidLibraryBuild.Build` を走らせます。`build/android/Export` に Gradle プロジェクトが出ます。続けて Unity 付属の OpenJDK でリリース AAR を作り、公開します。

```shell
export JAVA_HOME="/Applications/Unity/Hub/Editor/6000.3.10f1/PlaybackEngines/AndroidPlayer/OpenJDK"
cd build/android/Export
./gradlew :unityLibrary:assembleRelease --no-daemon
cd ../../..
scripts/publish-unity-aar.sh
```

`publish-unity-aar.sh` は `unity-classes.jar` を AAR の `classes.jar` にまとめ、`dev.uaal.intercomm:unity-player:1.0.0` として `android/maven` に上げます。書き出しに Gradle wrapper が無いときは、Export ディレクトリで Gradle 8.13 の wrapper を作ってから `assembleRelease` します。IL2CPP と NDK は Unity 付属のものを使います。

PlayerSettingsは、IL2CPP、Android arm64、minSdk 25、iOS 15、スプラッシュオフ、Run Without Focus オンです。Android のアプリケーション ID は `dev.uaal.intercomm` です。
