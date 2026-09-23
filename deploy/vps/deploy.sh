#!/usr/bin/env bash
# Deploys the given image to the "chatwoot_v2" swarm stack and waits for it to be healthy.
# Usage: deploy.sh <image>   (run from /opt/chatwoot-v2, which holds stack.yml and .env)
set -euo pipefail

IMAGE="${1:?usage: deploy.sh <image>}"
STACK=chatwoot_v2
APP_PORT="${APP_PORT:-3001}"
cd "$(dirname "$0")"

[ -f .env ] || { echo ".env not found in $(pwd)"; exit 1; }

docker pull "$IMAGE"

export CHATWOOT_IMAGE="$IMAGE" APP_PORT
docker stack deploy --with-registry-auth --detach=true -c stack.yml "$STACK"

echo "Waiting for ${STACK}_app to run $IMAGE and answer on :$APP_PORT..."
for _ in $(seq 1 90); do
  running=$(docker service ps "${STACK}_app" --filter desired-state=running --format '{{.Image}} {{.CurrentState}}' | head -n1)
  # Swarm may append @sha256:<digest> to the image name.
  if [[ "$running" == "$IMAGE"* && "$running" == *" Running "* ]] && curl -fsS "http://127.0.0.1:${APP_PORT}/api" >/dev/null 2>&1; then
    echo "Deploy OK: $running"
    curl -fsS "http://127.0.0.1:${APP_PORT}/api"; echo
    exit 0
  fi
  sleep 10
done

echo "Deploy did not become healthy in time. Recent app logs:"
docker service logs --tail 100 "${STACK}_app" || true
exit 1
