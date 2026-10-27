#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
failures=0

while IFS= read -r -d '' file; do
    case "$file" in
        makefile|*/modulefile|version.txt|*.sh)
            if LC_ALL=C grep -n $'[^\t -~]' "$PROJECT_ROOT/$file"; then
                printf 'Non-ASCII or control bytes found in %s\n' "$file" >&2
                failures=1
            fi
            ;;
    esac
done < <(git -C "$PROJECT_ROOT" ls-files -z)

if [[ $failures -ne 0 ]]; then
    exit 1
fi

printf 'ASCII source policy check passed\n'
