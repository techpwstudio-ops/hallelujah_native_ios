#!/bin/zsh
# Usage: Scripts/relaunch.sh [--quick|--clean]
#   (default)  rebuild, reinstall over the existing app (keeps data), launch
#   --quick    just terminate + launch, no build
#   --clean    rebuild, uninstall first (wipes app data), install, launch
set -e
cd "${0:A:h}/.."

DEVICE=${DEVICE:-E3774B69-2B27-46B9-89F2-C3C29DDD34C1}
SCHEME=${SCHEME:-"GHallelujah Staging"}
BUNDLE=com.hallelujah.user
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/GHallelujah-relaunch}
APP="$DD/Build/Products/${SCHEME#GHallelujah }-iphonesimulator/GHallelujah.app"

step() { print -P "%F{cyan}▶ $1%f"; }

xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
open -a Simulator

if [[ $1 != --quick ]]; then
  step "Building $SCHEME (live compile progress below)"
  xcodebuild build -project GHallelujah.xcodeproj -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$DD" \
    ONLY_ACTIVE_ARCH=YES 2>&1 | awk '
      /^(CompileSwift|SwiftCompile|Ld |CodeSign|ProcessInfoPlist|CompileAssetCatalog|CopySwiftLibs|LinkAssetCatalog)/ { n++; printf "  [%d] %s\n", n, substr($0,1,90) }
      / error: /   { print "  ✖ " $0 }
      /BUILD (SUCCEEDED|FAILED)/ { print "  " $0 }
    ' ; [[ ${pipestatus[1]} -eq 0 ]] || { print -P "%F{red}Build failed%f"; exit 1 }
fi

step "Stopping app"
xcrun simctl terminate "$DEVICE" $BUNDLE 2>/dev/null || true

if [[ $1 != --quick ]]; then
  [[ $1 == --clean ]] && { step "Uninstalling (wiping data)"; xcrun simctl uninstall "$DEVICE" $BUNDLE || true; }
  step "Installing"
  xcrun simctl install "$DEVICE" "$APP"
fi

step "Launching"
xcrun simctl launch "$DEVICE" $BUNDLE
print -P "%F{green}✔ Done%f"
