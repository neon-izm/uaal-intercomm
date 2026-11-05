#!/usr/bin/env bash
# Build UnityFramework.xcframework for device and simulator, then upload
# the iOS content catalog and the zipped framework to R2.
#
# The next app adds ios/UaalIntercomm as a local Swift package. Run this
# script first so Package.swift can see build/ios/UnityFramework.xcframework.
#
# Uses the open Unity editor when one is already serving this project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/uaal-intercomm"
BUILD="$ROOT/build/ios"
LOGS="$BUILD/logs"
VERSION="$(awk -F': ' '/m_EditorVersion:/{print $2; exit}' "$PROJECT/ProjectSettings/ProjectVersion.txt")"
UNITY="/Applications/Unity/Hub/Editor/${VERSION}/Unity.app/Contents/MacOS/Unity"
CONTENT_VERSION="$(awk -F= '/^CONTENT_VERSION=/{print $2; exit}' "$ROOT/scripts/hosting.env")"

export UNITY_PROJECT_PATH="$PROJECT"
mkdir -p "$LOGS"

editor_ready() {
  unity --no-banner --format json command --timeout 8 editor status >/dev/null 2>&1
}

run_editor_method() {
  local method="$1"
  local status="$BUILD/${2}"
  rm -f "$status"
  local log="$LOGS/${2%.status}-unity.log"
  unity --no-banner command --timeout 5400 script eval \
    --timeout 5400 \
    --code "UaalIntercomm.Editor.IosLibraryBuild.${method}(); return \"ok\";" \
    >"$log" 2>&1 &
  local pid=$!
  local deadline=$((SECONDS + 5400))
  local dropped=0
  while (( SECONDS < deadline )); do
    if [[ -f "$status" ]]; then
      break
    fi
    if [[ "$dropped" -eq 0 ]] && ! kill -0 "$pid" 2>/dev/null; then
      dropped=1
      if grep -q "Invalid response format" "$log"; then
        echo "editor connection dropped; waiting for ${method} to finish" >&2
      elif ! grep -q "error CS" "$log"; then
        echo "unity command exited before ${method} finished. See $log" >&2
        tail -40 "$log" >&2 || true
        exit 1
      else
        echo "Unity script failed to compile. See $log" >&2
        tail -40 "$log" >&2 || true
        exit 1
      fi
    fi
    sleep 10
  done
  if [[ "$pid" -ne 0 ]]; then
    wait "$pid" || true
  fi
  if [[ ! -f "$status" ]]; then
    echo "Unity did not finish ${method}. See $log" >&2
    tail -40 "$log" >&2 || true
    exit 1
  fi
  if [[ "$(cat "$status")" != "ok" ]]; then
    echo "Unity ${method} failed. See $status" >&2
    cat "$status" >&2
    exit 1
  fi
}

run_batch_method() {
  local method="$1"
  local status="$BUILD/${2}"
  rm -f "$status"
  local log="$LOGS/${2%.status}-unity.log"
  "$UNITY" -batchmode -nographics -quit \
    -projectPath "$PROJECT" \
    -buildTarget iOS \
    -executeMethod "UaalIntercomm.Editor.IosLibraryBuild.${method}" \
    -logFile "$log"
  if [[ ! -f "$status" || "$(cat "$status")" != "ok" ]]; then
    echo "Unity ${method} failed. See $log" >&2
    exit 1
  fi
}

run_unity() {
  if editor_ready; then
    run_editor_method "$1" "$2"
  else
    run_batch_method "$1" "$2"
  fi
}

archive_framework() {
  local project="$1"
  local sdk="$2"
  local archive="$3"
  local destination="generic/platform=iOS"
  if [[ "$sdk" == "iphonesimulator" ]]; then
    destination="generic/platform=iOS Simulator"
  fi
  local scheme_args=(-scheme UnityFramework)
  if ! xcodebuild -project "$project" -list 2>/dev/null | grep -q "UnityFramework"; then
    scheme_args=(-target UnityFramework)
  fi
  # シミュレータの既定アーキテクチャは x86_64。
  # Unity 6.3 は arm64 用の UnityRuntime.framework を別途持っているので、
  # 書き出し側で Simulator Architecture を ARM64 にしたうえで、ここでも arm64 に固定する。
  xcodebuild archive \
    -project "$project" \
    "${scheme_args[@]}" \
    -configuration Release \
    -sdk "$sdk" \
    -destination "$destination" \
    -archivePath "$archive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS=arm64 \
    EXCLUDED_ARCHS=x86_64
}

framework_in_archive() {
  local archive="$1"
  local product="$archive.xcarchive/Products/Library/Frameworks/UnityFramework.framework"
  if [[ -d "$product" ]]; then
    echo "$product"
    return
  fi
  local found
  found="$(find "$archive.xcarchive" -type d -name UnityFramework.framework | head -1)"
  if [[ -z "$found" ]]; then
    echo "UnityFramework.framework was not in $archive.xcarchive" >&2
    exit 1
  fi
  echo "$found"
}

echo "exporting Unity for device"
run_unity BuildForDevice device.status

echo "uploading content/${CONTENT_VERSION}/iOS"
"$ROOT/scripts/publish-r2.sh" "$PROJECT/ServerData/iOS" "content/${CONTENT_VERSION}/iOS"

echo "exporting Unity for simulator"
run_unity BuildForSimulator simulator.status

DEVICE_PROJ="$BUILD/DeviceSDK/Unity-iPhone.xcodeproj"
SIM_PROJ="$BUILD/SimulatorSDK/Unity-iPhone.xcodeproj"
if [[ ! -d "$DEVICE_PROJ" || ! -d "$SIM_PROJ" ]]; then
  echo "Unity did not write Unity-iPhone.xcodeproj" >&2
  exit 1
fi

echo "archiving UnityFramework"
archive_framework "$DEVICE_PROJ" iphoneos "$BUILD/device" 2>&1 | tee "$LOGS/device-xcode.log"
archive_framework "$SIM_PROJ" iphonesimulator "$BUILD/simulator" 2>&1 | tee "$LOGS/simulator-xcode.log"

DEVICE_FW="$(framework_in_archive "$BUILD/device")"
SIM_FW="$(framework_in_archive "$BUILD/simulator")"
XC="$BUILD/UnityFramework.xcframework"
rm -rf "$XC"
xcodebuild -create-xcframework \
  -framework "$DEVICE_FW" \
  -framework "$SIM_FW" \
  -output "$XC"

# Data は Unity-iPhone 側のリソースなので、UnityFramework だけを
# アーカイブすると framework に入らない。実行時は com.unity3d.framework の中を見る。
copy_data() {
  local source="$1"
  local destination="$2"
  if [[ ! -d "$source" ]]; then
    echo "missing Unity Data at $source" >&2
    exit 1
  fi
  rm -rf "$destination"
  ditto "$source" "$destination"
}
copy_data "$ROOT/build/ios/DeviceSDK/Data" "$XC/ios-arm64/UnityFramework.framework/Data"
copy_data "$ROOT/build/ios/SimulatorSDK/Data" "$XC/ios-arm64-simulator/UnityFramework.framework/Data"

while IFS= read -r interface; do
  sed -i '' 's/UnityFramework\.//g' "$interface"
done < <(find "$XC" -name "*.swiftinterface")

ZIP="$BUILD/UnityFramework.xcframework.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$XC" "$ZIP"
checksum="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "$checksum" > "$ZIP.sha256"
echo "checksum $checksum"

echo "uploading ios/${CONTENT_VERSION}/UnityFramework.xcframework.zip"
"$ROOT/scripts/publish-r2.sh" --file "$ZIP" "ios/${CONTENT_VERSION}/UnityFramework.xcframework.zip"
"$ROOT/scripts/publish-r2.sh" --file "$ZIP.sha256" "ios/${CONTENT_VERSION}/UnityFramework.xcframework.zip.sha256"

echo "xcframework: $XC"
echo "package: $ROOT/ios/UaalIntercomm"
