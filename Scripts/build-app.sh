#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

architectures=("$(uname -m)")
while [ "$#" -gt 0 ]; do
  case "$1" in
    --universal) architectures=(arm64 x86_64) ;;
    --preview) ;; # Accepted for older build instructions.
    *) echo 'Usage: Scripts/build-app.sh [--universal]' >&2; exit 1 ;;
  esac
  shift
done
destination="$PWD/dist/build/CopyShelf.app"
for running_pid in $(pgrep -x CopyShelf || true); do
  if [ "$(ps -p "$running_pid" -o comm=)" = "$destination/Contents/MacOS/CopyShelf" ]; then
    echo 'Quit the app at the build destination before replacing it.' >&2; exit 1
  fi
done
mkdir -p "$PWD/dist/build"
binary_paths=()
for architecture in "${architectures[@]}"; do
  scratch_path="$PWD/.build/release-$architecture"
  swift build --configuration release --arch "$architecture" --scratch-path "$scratch_path"
  binary_dir=$(swift build --configuration release --arch "$architecture" --scratch-path "$scratch_path" --show-bin-path)
  binary_paths+=("$binary_dir/CopyShelf")
done

staging=$(mktemp -d "${TMPDIR:-/tmp}/CopyShelf-build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app_path="$staging/CopyShelf.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [ "${#binary_paths[@]}" -gt 1 ]; then
  lipo -create "${binary_paths[@]}" -output "$app_path/Contents/MacOS/CopyShelf"
else
  cp "${binary_paths[0]}" "$app_path/Contents/MacOS/CopyShelf"
fi
cp Resources/Info.plist "$app_path/Contents/Info.plist"
icon_dir="$PWD/.build/AppIcon.iconset"
mkdir -p "$icon_dir"
swift Scripts/make-icon.swift "$icon_dir"
iconutil -c icns "$icon_dir" -o "$app_path/Contents/Resources/AppIcon.icns"
chmod +x "$app_path/Contents/MacOS/CopyShelf"
# Finder metadata can be attached to generated files on some macOS setups.
# Remove only the metadata that codesign rejects, leaving security attributes alone.
for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
  xattr -dr "$attribute" "$app_path" 2>/dev/null || true
done
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
rm -rf "$destination"
ditto --norsrc "$app_path" "$destination"
for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
  xattr -dr "$attribute" "$destination" 2>/dev/null || true
done
codesign --verify --strict "$destination"
printf '\nBuilt %s\n' "$destination"
printf 'Ad-hoc signed build: updates can require permission again. The installed app was not replaced.\n'
