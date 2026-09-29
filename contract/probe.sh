#!/usr/bin/env bash
# Start a throwaway Grafana for hand probing: probe.sh IMAGE NAME → prints the port. Stop with docker rm -f NAME.
set -euo pipefail
IMAGE=$1; NAME=$2; WORK=/tmp/claude-0/-opt/634dbec7-203a-4ca7-ab49-5ecfc466581d/scratchpad/probe-$NAME
mkdir -p "$WORK"; node "$(dirname "$0")/jwks.mjs" "$WORK"; chmod 644 "$WORK/jwks.json"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --rm --name "$NAME" -p 127.0.0.1::3000 --add-host=host.docker.internal:host-gateway -v "$WORK/jwks.json:/etc/grafana/jwks.json:ro" \
  -e GF_SECURITY_ADMIN_PASSWORD=contract -e GF_USERS_ALLOW_SIGN_UP=false -e GF_UNIFIED_ALERTING_MIN_INTERVAL=10s \
  -e GF_AUTH_JWT_ENABLED=true -e GF_AUTH_JWT_HEADER_NAME=X-JWT-Assertion -e GF_AUTH_JWT_JWK_SET_FILE=/etc/grafana/jwks.json \
  -e GF_AUTH_JWT_USERNAME_CLAIM=sub -e GF_AUTH_JWT_EMAIL_CLAIM=email -e GF_AUTH_JWT_AUTO_SIGN_UP=true -e GF_AUTH_JWT_URL_LOGIN=true \
  -e GF_AUTH_JWT_EXPECT_CLAIMS='{"iss":"https://contract.invalid/"}' "$IMAGE" >/dev/null
PORT=$(docker port "$NAME" 3000/tcp | head -1 | sed 's/.*://')
for i in $(seq 1 60); do curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break; sleep 1; done
echo "$PORT"
