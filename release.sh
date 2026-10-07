#!/bin/bash
# Builds a signed, notarized TrashToss DMG ready to share.
#
# Usage: ./release.sh [--dry-run] [--publish]
#   --dry-run  skip Developer ID signing and notarization. Combined with --publish, the DMG
#              goes up as a GitHub pre-release with "Open Anyway" install instructions.
#   --publish  also create a GitHub Release v<version> with the DMG attached
#
# The version comes from CFBundleShortVersionString in Support/Info.plist; bump it
# (and CFBundleVersion) before each release.
#
# One-time setup (after joining the Apple Developer Program):
#   1. Create a "Developer ID Application" certificate and install it in your keychain.
#   2. Store notarization credentials (use an app-specific password from appleid.apple.com):
#        xcrun notarytool store-credentials TrashToss-notary \
#            --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-password>
#
# Optional overrides:
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)" (auto-detected by default)
#   NOTARY_PROFILE  keychain profile name for notarytool (default: TrashToss-notary)
set -euo pipefail
cd "$(dirname "$0")"

DRY_RUN=0
PUBLISH=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --publish) PUBLISH=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

NOTARY_PROFILE="${NOTARY_PROFILE:-TrashToss-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
APP=build/TrashToss.app
DMG="build/TrashToss-$VERSION.dmg"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------

if [[ $DRY_RUN == 0 ]]; then
    if [[ -z "${SIGN_IDENTITY:-}" ]]; then
        SIGN_IDENTITY="$(security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
    fi
    [[ -n "$SIGN_IDENTITY" ]] || fail "No \"Developer ID Application\" certificate found in your keychain.
Create one at https://developer.apple.com/account/resources/certificates (or Xcode > Settings > Accounts),
then run this again. Use --dry-run to test packaging without it."

    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || fail "No notarization credentials stored as \"$NOTARY_PROFILE\". Run:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-password>"
fi

if [[ $PUBLISH == 1 ]]; then
    command -v gh >/dev/null || fail "--publish needs the GitHub CLI (brew install gh)."
    gh release view "v$VERSION" >/dev/null 2>&1 && fail "Release v$VERSION already exists. Bump the version in Support/Info.plist."
    [[ -z "$(git status --porcelain)" ]] || fail "Commit your changes before publishing."
    git fetch -q origin
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse '@{u}')" ]] || fail "Push your commits before publishing."
fi

# --- Build & sign ------------------------------------------------------------

step "Building TrashToss $VERSION (universal)"
./build.sh --universal

if [[ $DRY_RUN == 0 ]]; then
    step "Signing with $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
fi

# --- DMG ---------------------------------------------------------------------

step "Creating $DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "TrashToss" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

if [[ $DRY_RUN == 1 ]]; then
    if [[ $PUBLISH == 1 ]]; then
        step "Publishing unsigned GitHub pre-release v$VERSION"
        gh release create "v$VERSION" "$DMG" --prerelease --title "TrashToss $VERSION (unsigned preview)" \
            --notes-file Support/unsigned-release-notes.md
    fi
    step "Done (unsigned, not notarized): $DMG"
    exit 0
fi

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

# --- Notarize ----------------------------------------------------------------

step "Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

step "Verifying Gatekeeper acceptance"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# --- Publish -----------------------------------------------------------------

if [[ $PUBLISH == 1 ]]; then
    step "Publishing GitHub Release v$VERSION"
    gh release create "v$VERSION" "$DMG" --title "TrashToss $VERSION" --generate-notes
fi

step "Done: $DMG"
