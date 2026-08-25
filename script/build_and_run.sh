#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WTM"
BUNDLE_ID="de.powtac.whatthemodel"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Run"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
source "$ROOT_DIR/scripts/load-local-environment"
load_local_environment "$ROOT_DIR"

build_settings=()
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
  build_settings+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
fi

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

/usr/bin/xcodebuild \
  -quiet \
  -project "$ROOT_DIR/WTM.xcodeproj" \
  -scheme WTM \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  "${build_settings[@]}" \
  build

if [[ ! -x "$APP_BINARY" ]]; then
  echo "built app binary not found: $APP_BINARY" >&2
  exit 1
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if /usr/bin/pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not remain running after launch" >&2
    exit 1
    ;;
esac
