#!/usr/bin/env bash
# Builds MailCore.xcframework via Carthage and installs it into HostMailCore/Frameworks/.
# Run once after cloning the repo (or whenever MailCore2 needs an update).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="$REPO_ROOT/HostMailCore/Frameworks"
WORK_DIR="$REPO_ROOT/.mailcore-build"
TARGET_FRAMEWORK="$FRAMEWORKS_DIR/MailCore.xcframework"

echo "==> HostMail :: MailCore2 XCFramework setup"
echo "    repo:        $REPO_ROOT"
echo "    work dir:    $WORK_DIR"
echo "    install to:  $TARGET_FRAMEWORK"
echo

if ! command -v carthage >/dev/null 2>&1; then
    echo "ERROR: Carthage is not installed."
    echo "Install with:  brew install carthage"
    exit 1
fi

CARTHAGE_VERSION="$(carthage version 2>/dev/null | head -n1)"
echo "==> Carthage version: $CARTHAGE_VERSION"

mkdir -p "$WORK_DIR"
mkdir -p "$FRAMEWORKS_DIR"

cd "$WORK_DIR"
echo 'github "MailCore/mailcore2"' > Cartfile

echo "==> Step 1/3: carthage update --no-build  (checkout sources only)"
carthage update --no-build

MAILCORE_PBXPROJ="$WORK_DIR/Carthage/Checkouts/mailcore2/build-mac/mailcore2.xcodeproj/project.pbxproj"
if [ ! -f "$MAILCORE_PBXPROJ" ]; then
    echo "ERROR: expected pbxproj not found at $MAILCORE_PBXPROJ"
    exit 1
fi

echo "==> Step 2/3: patch deployment targets in mailcore2.xcodeproj"
echo "    (Xcode 15+ removed libarclite; old iOS 6/macOS 10.7 targets must be raised)"
# BSD sed (macOS) syntax: -i '' for in-place
sed -i '' -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+/IPHONEOS_DEPLOYMENT_TARGET = 14.0/g' "$MAILCORE_PBXPROJ"
sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = [0-9.]+/MACOSX_DEPLOYMENT_TARGET = 11.0/g' "$MAILCORE_PBXPROJ"

echo "    Patched targets:"
grep -E "(IPHONEOS|MACOSX)_DEPLOYMENT_TARGET" "$MAILCORE_PBXPROJ" | sort -u

echo "==> Step 3/3: carthage build --use-xcframeworks --platform iOS,macOS"
echo "    (this can take 10+ minutes — compiling libetpan, ICU, etc.)"
carthage build --use-xcframeworks --platform iOS,macOS --no-use-binaries

BUILT_XCFRAMEWORK="$WORK_DIR/Carthage/Build/MailCore.xcframework"
if [ ! -d "$BUILT_XCFRAMEWORK" ]; then
    echo "ERROR: Carthage finished but $BUILT_XCFRAMEWORK was not produced."
    echo "       Inspect $WORK_DIR/Carthage/Build/ to see what was built."
    exit 1
fi

echo "==> Installing XCFramework into HostMailCore/Frameworks/"
rm -rf "$TARGET_FRAMEWORK"
cp -R "$BUILT_XCFRAMEWORK" "$TARGET_FRAMEWORK"

echo
echo "==> Done. MailCore.xcframework is ready at:"
echo "    $TARGET_FRAMEWORK"
echo
echo "Next:"
echo "  1. cd $REPO_ROOT"
echo "  2. xcodegen generate"
echo "  3. open HostMail.xcodeproj   (or just build)"
