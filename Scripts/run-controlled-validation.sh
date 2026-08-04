#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --app /absolute/path/App.app|Executable --database /tmp/path.sqlite3 [--copy-from /tmp/source.sqlite3]" >&2
  exit 64
}

app_path=""
database_path=""
copy_from=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) [[ $# -ge 2 ]] || usage; app_path="$2"; shift 2 ;;
    --database) [[ $# -ge 2 ]] || usage; database_path="$2"; shift 2 ;;
    --copy-from) [[ $# -ge 2 ]] || usage; copy_from="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$app_path" && -n "$database_path" ]] || usage
[[ "$database_path" == /tmp/* || "$database_path" == /private/tmp/* ]] || {
  echo "refusing controlled validation: database must be under /tmp" >&2
  exit 78
}

if [[ -n "$copy_from" ]]; then
  [[ -f "$copy_from" ]] || { echo "copy source does not exist: $copy_from" >&2; exit 66; }
  mkdir -p "$(dirname "$database_path")"
  cp -f "$copy_from" "$database_path"
else
  mkdir -p "$(dirname "$database_path")"
  [[ -e "$database_path" ]] || : > "$database_path"
fi

if [[ -d "$app_path" ]]; then
  executable_path="$app_path/Contents/MacOS/$(basename "$app_path" .app)"
else
  executable_path="$app_path"
fi
[[ -x "$executable_path" ]] || { echo "executable is not runnable: $executable_path" >&2; exit 66; }

echo "executable_path=$executable_path"
echo "temporary_database_path=$database_path"
echo "temporary_copy=YES"
echo "formal_database_opened=NO"
echo "launch_mode=direct-executable"

exec env SPOTIFYLYRICS_DATABASE_PATH="$database_path" "$executable_path"
