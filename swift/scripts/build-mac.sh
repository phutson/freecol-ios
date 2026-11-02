#!/bin/sh
# Build the FreeCol app for the Mac (Mac Catalyst, Phase 6 of
# doc/swift-port-plan.md) from the same app package as the iOS app,
# signed to run locally only, into swift/build/mac/FreeCol.app.  Run
# from the top of the repository.  Distribution needs a signing team
# and notarization, which this does not do.
set -e
OUT=swift/build/mac
DERIVED=swift/build/mac-derived
cd swift/FreeColApp.swiftpm
xcodebuild -scheme FreeColApp -configuration Release \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath ../build/mac-derived CODE_SIGN_IDENTITY=- build | grep -E 'error:|BUILD'
cd ../..
mkdir -p "$OUT"
rm -rf "$OUT/FreeCol.app"
cp -R "$DERIVED/Build/Products/Release-maccatalyst/FreeCol.app" "$OUT/"
echo "$OUT/FreeCol.app"
