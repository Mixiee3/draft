#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -q --product DraftMCP >&2
exec .build/debug/DraftMCP "$@"
