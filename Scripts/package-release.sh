#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -eq 0 ] || { echo 'Usage: Scripts/package-release.sh' >&2; exit 1; }
source_app="$PWD/dist/build/CopyShelf.app"
[ -d "$source_app" ] || { echo 'Run Scripts/build-app.sh --universal first.' >&2; exit 1; }
staging=$(mktemp -d "${TMPDIR:-/tmp}/CopyShelf-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app_path="$staging/CopyShelf.app"
ditto --norsrc "$source_app" "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'App version must be numeric major.minor.patch.' >&2; exit 1; }
source_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
source_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
built_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_path/Contents/Info.plist")
[ "$version" = "$source_version" ] && [ "$source_build" = "$built_build" ] || {
  echo 'Built app version differs from Resources/Info.plist. Rebuild before packaging.' >&2; exit 1;
}
architectures=$(lipo -archs "$app_path/Contents/MacOS/CopyShelf")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
  echo 'Run Scripts/build-app.sh --universal to include both Mac architectures.' >&2; exit 1;
}
for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
  xattr -dr "$attribute" "$app_path" 2>/dev/null || true
done
codesign --verify --strict "$app_path"
archive="$staging/CopyShelf-$version-macOS-unsigned.zip"
ditto --norsrc --noextattr --noqtn -c -k --keepParent "$app_path" "$archive"
python3 Scripts/check-release-archive.py "$staging"
dmg_contents="$staging/dmg"
mkdir -p "$dmg_contents"
ditto --norsrc "$app_path" "$dmg_contents/CopyShelf.app"
ln -s /Applications "$dmg_contents/Applications"
cp docs/INSTALL.txt "$dmg_contents/Read me.txt"
disk_image="$staging/CopyShelf-$version-macOS-unsigned.dmg"
hdiutil create -volname CopyShelf -srcfolder "$dmg_contents" -format UDZO -ov "$disk_image"
for artifact in "$archive" "$disk_image"; do
  (cd "$staging" && shasum -a 256 "$(basename "$artifact")" > "$(basename "$artifact").sha256")
done
mkdir -p dist
for artifact in "$archive" "$disk_image"; do
  ditto "$artifact" "$PWD/dist/$(basename "$artifact")"
  cp "$artifact.sha256" "$PWD/dist/$(basename "$artifact").sha256"
  printf 'Packaged %s\n' "$PWD/dist/$(basename "$artifact")"
done
printf 'Community beta: not Apple notarized. Updates may require permissions again.\n'
