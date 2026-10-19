#!/bin/zsh
# Usage: Scripts/relaunch.sh [--local|--dev|--prod] [--quick|--clean]
#
# Environment (default --dev):
#   --local    "Hallelujah Development"  → localhost:3000 API (Debug build)
#   --dev      "Hallelujah Staging"      → qa.api.hallelujah.today (QA stack)
#   --prod     "Hallelujah Production"   → api.hallelujah.today
#   (SCHEME="Hallelujah …" in the environment still works; a flag wins over it)
#
# Mode (default: rebuild, reinstall over the existing app, keeps data):
#   --quick    just terminate + launch, no build
#   --clean    rebuild, uninstall first (wipes app data), install, launch
#
# Examples:
#   Scripts/relaunch.sh --prod
#   Scripts/relaunch.sh --local --clean
set -e
SELF=${0:A}
cd "${SELF:h}/.."

DEVICE=${DEVICE:-E3774B69-2B27-46B9-89F2-C3C29DDD34C1}
SCHEME=${SCHEME:-"Hallelujah Staging"}
BUNDLE=com.hallelujah.user
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/Hallelujah-relaunch}

MODE=build
for arg in "$@"; do
  case $arg in
    --local)       SCHEME="Hallelujah Development" ;;
    --dev)         SCHEME="Hallelujah Staging" ;;
    --prod)        SCHEME="Hallelujah Production" ;;
    --quick)       MODE=quick ;;
    --clean)       MODE=clean ;;
    -h|--help)     sed -n '2,/^set -e/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             print -P "%F{red}Unknown option: $arg%f (try --help)"; exit 2 ;;
  esac
done

# Build-products folder is named after the Xcode configuration, which only
# matches the scheme name for Staging (Production builds with `Release`).
case $SCHEME in
  *Production)  CONFIG=Release ;;
  *Development) CONFIG=Debug ;;
  *)            CONFIG=${SCHEME#Hallelujah } ;;
esac
APP="$DD/Build/Products/$CONFIG-iphonesimulator/Hallelujah.app"

step() { print -P "%F{cyan}▶ $1%f"; }

xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
open -a Simulator

if [[ $MODE != quick ]]; then
  step "Building $SCHEME (live compile progress below)"
  xcodebuild build -project Hallelujah.xcodeproj -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$DD" \
    ONLY_ACTIVE_ARCH=YES 2>&1 | awk '
      /^(CompileSwift|SwiftCompile|Ld |CodeSign|ProcessInfoPlist|CompileAssetCatalog|CopySwiftLibs|LinkAssetCatalog)/ { n++; printf "  [%d] %s\n", n, substr($0,1,90) }
      / error: /   { print "  ✖ " $0 }
      /BUILD (SUCCEEDED|FAILED)/ { print "  " $0 }
    ' ; [[ ${pipestatus[1]} -eq 0 ]] || { print -P "%F{red}Build failed%f"; exit 1 }
fi

step "Stopping app"
xcrun simctl terminate "$DEVICE" $BUNDLE 2>/dev/null || true

if [[ $MODE != quick ]]; then
  [[ $MODE == clean ]] && { step "Uninstalling (wiping data)"; xcrun simctl uninstall "$DEVICE" $BUNDLE || true; }
  step "Installing"
  xcrun simctl install "$DEVICE" "$APP"
fi

step "Launching ($SCHEME)"
xcrun simctl launch "$DEVICE" $BUNDLE
print -P "%F{green}✔ Done%f"
