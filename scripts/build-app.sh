#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
orbit_required_assets=(batman-cutout.png batman-reference.png)
for orbit_asset_name in "${orbit_required_assets[@]}"; do
  orbit_source_asset="$PWD/Sources/Orbit/Assets/$orbit_asset_name"
  if [[ ! -f "$orbit_source_asset" || ! -s "$orbit_source_asset" ]]; then
    print -u2 -- "Missing or empty required companion asset: $orbit_source_asset"
    exit 1
  fi
done
mkdir -p .build/cache .build/config .build/security build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
ORBIT_APP="$PWD/build/Orbit.app"
mkdir -p "$ORBIT_APP/Contents/MacOS" "$ORBIT_APP/Contents/Resources"
cp .build/release/Orbit "$ORBIT_APP/Contents/MacOS/Orbit"
cp Resources/Info.plist "$ORBIT_APP/Contents/Info.plist"
# CompanionView checks this signed-app location before SwiftPM's debug fallback.
ditto .build/release/Orbit_Orbit.bundle "$ORBIT_APP/Contents/Resources/Orbit_Orbit.bundle"
for orbit_asset_name in "${orbit_required_assets[@]}"; do
  orbit_source_asset="$PWD/Sources/Orbit/Assets/$orbit_asset_name"
  orbit_packaged_asset="$ORBIT_APP/Contents/Resources/Orbit_Orbit.bundle/$orbit_asset_name"
  if [[ ! -f "$orbit_packaged_asset" || ! -s "$orbit_packaged_asset" ]]; then
    print -u2 -- "Missing or empty packaged companion asset: $orbit_packaged_asset"
    exit 1
  fi
  if ! cmp -s "$orbit_source_asset" "$orbit_packaged_asset"; then
    print -u2 -- "Packaged companion asset differs from its source: $orbit_packaged_asset"
    exit 1
  fi
done
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$ORBIT_APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$ORBIT_APP"
codesign --verify --strict "$ORBIT_APP"
plutil -lint "$ORBIT_APP/Contents/Info.plist"
print "Built $ORBIT_APP"
