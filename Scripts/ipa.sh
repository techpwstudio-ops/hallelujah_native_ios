#!/bin/bash
# Archive the Production scheme (Release config, production backend) and
# export an App Store Connect IPA, then open the archive in Xcode Organizer.
# Native counterpart of the Flutter app's ipa.sh --prod.
#
# Needs Config/Secrets.xcconfig with HALLELUJAH_DEVELOPMENT_TEAM and the three
# production secrets, and Xcode signed in to an account on that team.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/GHallelujah.xcodeproj"
SCHEME="GHallelujah Production"
EXPORT_OPTIONS="$ROOT/Config/ExportOptions.plist"
SECRETS="$ROOT/Config/Secrets.xcconfig"

for key in HALLELUJAH_DEVELOPMENT_TEAM HALLELUJAH_API_SECRET HALLELUJAH_OTP_SECRET_1 HALLELUJAH_OTP_SECRET_2; do
  if ! grep -Eq "^[[:space:]]*$key[[:space:]]*=[[:space:]]*[^[:space:]]" "$SECRETS" 2>/dev/null; then
    echo "ERROR: $key is missing from $SECRETS"
    exit 1
  fi
done

# Archives under ~/Library/Developer/Xcode/Archives show up in Organizer.
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Hallelujah $(date +%Y-%m-%d\ %H.%M.%S).xcarchive"
EXPORT_PATH="$ROOT/build/ipa"

echo "Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

echo "Exporting IPA..."
rm -rf "$EXPORT_PATH"
if xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates; then
  echo ""
  echo "Done: $EXPORT_PATH"
else
  echo ""
  echo "IPA export failed. The archive is ready; distribute it from Organizer."
fi

open "$ARCHIVE_PATH"
