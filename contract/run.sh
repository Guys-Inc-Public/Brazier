#!/usr/bin/env bash
# Start one Grafana in Docker, run the contract tests against it, remove it.
#   contract/run.sh grafana/grafana-oss:11.6.5
# Needs docker and node 22+. The JWT tests want a JWKS file the container can read: run.sh writes it.
set -euo pipefail
IMAGE=${1:-grafana/grafana-oss:11.6.5}
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="brazier-contract-$$"
WORK="$(mktemp -d)"
PASSWORD=contract
node "$HERE/jwks.mjs" "$WORK"           # writes jwks.json + private key for the tests
chmod 644 "$WORK/jwks.json"
docker run -d --rm --name "$NAME" -p 127.0.0.1::3000 \
  --add-host=host.docker.internal:host-gateway \
  -v "$WORK/jwks.json:/etc/grafana/jwks.json:ro" \
  -e GF_SECURITY_ADMIN_PASSWORD="$PASSWORD" \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -e GF_UNIFIED_ALERTING_MIN_INTERVAL=10s \
  -e GF_AUTH_JWT_ENABLED=true \
  -e GF_AUTH_JWT_HEADER_NAME=X-JWT-Assertion \
  -e GF_AUTH_JWT_JWK_SET_FILE=/etc/grafana/jwks.json \
  -e GF_AUTH_JWT_USERNAME_CLAIM=sub \
  -e GF_AUTH_JWT_EMAIL_CLAIM=email \
  -e GF_AUTH_JWT_AUTO_SIGN_UP=true \
  -e GF_AUTH_JWT_URL_LOGIN=true \
  -e GF_AUTH_JWT_EXPECT_CLAIMS='{"iss":"https://contract.invalid/"}' \
  "$IMAGE" >/dev/null
PORT=$(docker port "$NAME" 3000/tcp | head -1 | sed 's/.*://')
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
export GRAFANA_URL="http://127.0.0.1:$PORT" GRAFANA_ADMIN_PASSWORD="$PASSWORD" CONTRACT_WORK="$WORK"
for i in $(seq 1 60); do
  if curl -fsS "$GRAFANA_URL/api/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
echo "== $IMAGE at $GRAFANA_URL: $(curl -fsS "$GRAFANA_URL/api/health" | tr -d '\n')"
cd "$HERE" && node --test --test-concurrency=1 grafana.test.mjs
