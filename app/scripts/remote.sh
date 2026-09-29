#!/usr/bin/env bash
# Stage app/ on the Mac mini and run a Makefile target there as the build user.
#   scripts/remote.sh build-sim | run-sim | archive | upload
# The Mac is reached key-only as cam; builds run as claude so DerivedData and signing live in that account.
set -euo pipefail
HOST=${BRAZIER_MAC:-cam@192.168.68.155}
TARGET=${1:-build-sim}
shift || true
# Remaining arguments are make variables, e.g. SEED_URL=https://… SEED_TOKEN=…
EXTRA=""
for arg in "$@"; do EXTRA+=" $(printf '%q' "$arg")"; done
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
rsync -a --delete --exclude Brazier.xcodeproj --exclude DerivedData --exclude '.DS_Store' "$APP_DIR/" "$HOST:/Users/Shared/brazier/app/"
ssh "$HOST" "chmod -R a+rwX /Users/Shared/brazier 2>/dev/null; sudo -n -u claude env HOME=/Users/claude /bin/zsh -lc 'cd /Users/Shared/brazier/app && make $TARGET$EXTRA'"
