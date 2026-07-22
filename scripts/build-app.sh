#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
module_cache_directory="${AGENT_CONTROLLER_MODULE_CACHE_PATH:-$project_root/.build/ModuleCache}"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw "$project_root/Resources/Info.plist")"
signing_fingerprint="${AGENT_CONTROLLER_SIGNING_SHA1:-}"
use_stable_signing=0

if [[ -n "${AGENT_CONTROLLER_SIGNING_FILE:-}" ]]; then
  identity_file="$AGENT_CONTROLLER_SIGNING_FILE"
else
  identity_file="$project_root/.agent-controller-signing-identity"
  if [[ ! -f "$identity_file" ]]; then
    common_git_directory="$(git -C "$project_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [[ -n "$common_git_directory" ]]; then
      primary_identity_file="$(dirname "$common_git_directory")/.agent-controller-signing-identity"
      if [[ -f "$primary_identity_file" ]]; then
        identity_file="$primary_identity_file"
      fi
    fi
  fi
fi

if [[ -z "$signing_fingerprint" && -f "$identity_file" ]]; then
  signing_fingerprint="$(tr -d '[:space:]' < "$identity_file")"
fi
if [[ -n "$signing_fingerprint" ]]; then
  signing_fingerprint="${signing_fingerprint:u}"
  if ! print -r -- "$signing_fingerprint" | grep -Eq '^[0-9A-F]{40}$'; then
    print -u2 "error: the stable signing fingerprint must be exactly 40 hexadecimal characters"
    exit 1
  fi
  use_stable_signing=1
  default_keychain="$(security default-keychain -d user | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//')"
  keychain_path="${AGENT_CONTROLLER_KEYCHAIN_PATH:-$default_keychain}"
  identity_matches="$(security find-identity -v -p codesigning "$keychain_path" 2>/dev/null | grep -c "$signing_fingerprint" || true)"
  if [[ "$identity_matches" -ne 1 ]]; then
    print -u2 "error: the pinned signing identity is unavailable in $keychain_path"
    exit 1
  fi
fi

mkdir -p "$module_cache_directory"
export CLANG_MODULE_CACHE_PATH="$module_cache_directory"

"$project_root/scripts/check-source-size.sh"
swift build --disable-sandbox -c "$configuration"
binary_directory="$(swift build --disable-sandbox -c "$configuration" --show-bin-path)"
app_directory="$project_root/.build/Agent Controller.app"
staging_directory="$(mktemp -d "$project_root/.build/agent-controller-app.XXXXXX")"
staged_app="$staging_directory/Agent Controller.app"
previous_app="$staging_directory/Previous Agent Controller.app"

cleanup() {
  rm -rf "$staging_directory"
}
trap cleanup EXIT

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_directory/AgentController" "$staged_app/Contents/MacOS/AgentController"
cp "$project_root/Resources/Info.plist" "$staged_app/Contents/Info.plist"
chmod +x "$staged_app/Contents/MacOS/AgentController"

if [[ -n "${AGENT_CONTROLLER_BUNDLE_VERSION:-}" ]]; then
  if ! print -r -- "$AGENT_CONTROLLER_BUNDLE_VERSION" | grep -Eq '^[0-9]+([.][0-9]+){0,2}$'; then
    print -u2 "error: AGENT_CONTROLLER_BUNDLE_VERSION must contain one to three numeric components"
    exit 1
  fi
  plutil -replace CFBundleVersion -string "$AGENT_CONTROLLER_BUNDLE_VERSION" "$staged_app/Contents/Info.plist"
fi

if [[ "$use_stable_signing" == "1" ]]; then
  designated_source="=designated => identifier \"$bundle_identifier\" and anchor = H\"$signing_fingerprint\""
  verification_requirement="=identifier \"$bundle_identifier\" and anchor = H\"$signing_fingerprint\""
  /usr/bin/codesign \
    --force \
    --sign "$signing_fingerprint" \
    --keychain "$keychain_path" \
    --requirements "$designated_source" \
    "$staged_app"
  /usr/bin/codesign --verify --strict --verbose=2 -R "$verification_requirement" "$staged_app"
  print -u2 "stable local signature applied once; Accessibility survives version changes"
else
  /usr/bin/codesign --force --sign - "$staged_app"
  print -u2 "local ad-hoc signature applied once; session switching works, but RT Accessibility may reset after rebuilds"
fi
/usr/bin/codesign --verify --strict --verbose=2 "$staged_app"

if [[ -e "$app_directory" ]]; then
  mv "$app_directory" "$previous_app"
fi
if ! mv "$staged_app" "$app_directory"; then
  if [[ -e "$previous_app" ]]; then
    mv "$previous_app" "$app_directory"
  fi
  print -u2 "error: could not replace the app bundle"
  exit 1
fi

echo "$app_directory"
