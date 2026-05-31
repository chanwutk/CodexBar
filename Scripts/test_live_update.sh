#!/usr/bin/env bash
set -euo pipefail

PREV_TAG=${1:?"pass previous release tag (e.g. v0.1.0)"}
CUR_TAG=${2:?"pass current release tag (e.g. v0.1.1)"}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREV_VER=${PREV_TAG#v}
APP_NAME="CodexBar"

if [[ -f "$ROOT/.mac-release.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/.mac-release.env"
fi
# shellcheck disable=SC1091
source "$ROOT/Scripts/release_artifacts.sh"

RELEASE_REPO=${MAC_RELEASE_REPO:-chanwutk/CodexBar}
ZIP_NAME=$(codexbar_app_zip_name "$PREV_VER" "${ARCHES:-arm64 x86_64}")
ZIP_URL="https://github.com/${RELEASE_REPO}/releases/download/${PREV_TAG}/${ZIP_NAME}"
TMP_DIR=$(mktemp -d /tmp/codexbar-live.XXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading previous release $PREV_TAG from $ZIP_URL"
curl -L -o "$TMP_DIR/prev.zip" "$ZIP_URL"

echo "Installing previous release to /Applications/${APP_NAME}.app"
rm -rf /Applications/${APP_NAME}.app
ditto -x -k "$TMP_DIR/prev.zip" "$TMP_DIR"
ditto "$TMP_DIR/${APP_NAME}.app" /Applications/${APP_NAME}.app

echo "Launching previous build…"
open -n /Applications/${APP_NAME}.app
sleep 4

cat <<'MSG'
Manual step: trigger "Check for Updates…" in the app and install the update.
Expect to land on the newly released version. When done, confirm below.
MSG

read -rp "Did the update succeed from ${PREV_TAG} to ${CUR_TAG}? (y/N) " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Live update test NOT confirmed; failing per RUN_SPARKLE_UPDATE_TEST." >&2
  exit 1
fi

echo "Live update test confirmed."
