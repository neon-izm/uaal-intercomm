#!/usr/bin/env bash
# Publish build/android/Export/unityLibrary as a Maven AAR on R2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AAR="$ROOT/build/android/Export/unityLibrary/build/outputs/aar/unityLibrary-release.aar"
STAGE="$ROOT/build/android/maven/dev/uaal/intercomm/unity-player/1.0.0"
META="$ROOT/build/android/maven/dev/uaal/intercomm/unity-player"

if [[ ! -f "$AAR" ]]; then
  echo "missing $AAR" >&2
  exit 1
fi

mkdir -p "$STAGE" "$META"
CLASSES_JAR="$ROOT/build/android/Export/unityLibrary/libs/unity-classes.jar"
if [[ ! -f "$CLASSES_JAR" ]]; then
  echo "missing $CLASSES_JAR" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$AAR" -d "$WORK/aar"
python3 - "$WORK/aar/classes.jar" "$CLASSES_JAR" <<'PY'
import sys
import zipfile

destination, unity_jar = sys.argv[1:]
entries = {}
for path in (destination, unity_jar):
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = info.filename
            if name.startswith("META-INF/") and name.endswith((".SF", ".RSA", ".DSA")):
                continue
            entries[name] = archive.read(name)
with zipfile.ZipFile(destination, "w") as archive:
    for name, data in entries.items():
        archive.writestr(name, data)
PY
rm -rf "$WORK/aar/libs"
rm -f "$STAGE/unity-player-1.0.0.aar"
(
  cd "$WORK/aar"
  zip -qr "$STAGE/unity-player-1.0.0.aar" .
)
cat > "$STAGE/unity-player-1.0.0.pom" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>dev.uaal.intercomm</groupId>
  <artifactId>unity-player</artifactId>
  <version>1.0.0</version>
  <packaging>aar</packaging>
  <dependencies>
    <dependency>
      <groupId>androidx.appcompat</groupId>
      <artifactId>appcompat</artifactId>
      <version>1.6.1</version>
    </dependency>
    <dependency>
      <groupId>androidx.core</groupId>
      <artifactId>core</artifactId>
      <version>1.9.0</version>
    </dependency>
    <dependency>
      <groupId>androidx.constraintlayout</groupId>
      <artifactId>constraintlayout</artifactId>
      <version>2.1.4</version>
    </dependency>
    <dependency>
      <groupId>androidx.games</groupId>
      <artifactId>games-activity</artifactId>
      <version>3.0.5</version>
    </dependency>
  </dependencies>
</project>
EOF
cat > "$META/maven-metadata.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>dev.uaal.intercomm</groupId>
  <artifactId>unity-player</artifactId>
  <versioning>
    <latest>1.0.0</latest>
    <release>1.0.0</release>
    <versions>
      <version>1.0.0</version>
    </versions>
  </versioning>
</metadata>
EOF

CHECK="$(mktemp -d)"
unzip -p "$STAGE/unity-player-1.0.0.aar" classes.jar > "$CHECK/classes.jar"
unzip -l "$STAGE/unity-player-1.0.0.aar" > "$CHECK/list.txt"
jar tf "$CHECK/classes.jar" > "$CHECK/classes.txt"
if ! grep -q 'com/unity3d/player/UnityPlayerForActivityOrService.class' "$CHECK/classes.txt"; then
  echo "UnityPlayer classes were not merged into the AAR" >&2
  rm -rf "$CHECK"
  exit 1
fi
if ! grep -q 'jni/arm64-v8a/libunity.so' "$CHECK/list.txt"; then
  echo "AAR is missing arm64 libunity.so" >&2
  rm -rf "$CHECK"
  exit 1
fi
rm -rf "$CHECK"

while IFS= read -r -d '' file; do
  case "$file" in
    *.sha1|*.sha256) continue ;;
  esac
  shasum -a 1 "$file" | awk '{print $1}' > "${file}.sha1"
  shasum -a 256 "$file" | awk '{print $1}' > "${file}.sha256"
done < <(find "$ROOT/build/android/maven" -type f -print0)

"$ROOT/scripts/publish-r2.sh" "$ROOT/build/android/maven" android/maven
echo "published dev.uaal.intercomm:unity-player:1.0.0"
