#!/usr/bin/env bash
# Copy the app's MongoDB database into a fresh MongoDB container and compare
# per-collection document counts between source and target.
#
# Required environment (passed by name, never echoed):
#   SOURCE_MONGO_URI   connection string of the source database
# Optional environment:
#   DOCKER_NETWORK     docker network that can reach the source (default: host)
#   TARGET_CONTAINER   name of the fresh target container (default: mongo-migration-target)
#   TARGET_PORT        loopback port for the target when DOCKER_NETWORK=host (default: 27018)
#   MONGO_IMAGE        MongoDB image providing mongod/mongodump/mongorestore (default: mongo:7.0)
#
# The app stores no files in object storage, so there is no bucket to mirror.
set -euo pipefail

: "${SOURCE_MONGO_URI:?set SOURCE_MONGO_URI in the environment}"
DOCKER_NETWORK="${DOCKER_NETWORK:-host}"
TARGET_CONTAINER="${TARGET_CONTAINER:-mongo-migration-target}"
TARGET_PORT="${TARGET_PORT:-27018}"
MONGO_IMAGE="${MONGO_IMAGE:-mongo:7.0}"

if docker container inspect "$TARGET_CONTAINER" >/dev/null 2>&1; then
  echo "target container $TARGET_CONTAINER already exists; remove it or set TARGET_CONTAINER" >&2
  exit 1
fi

run_net=(--network "$DOCKER_NETWORK")
if [ "$DOCKER_NETWORK" = host ]; then
  target_uri="mongodb://127.0.0.1:${TARGET_PORT}"
  docker run -d --name "$TARGET_CONTAINER" -p "127.0.0.1:${TARGET_PORT}:27017" "$MONGO_IMAGE" >/dev/null
else
  target_uri="mongodb://${TARGET_CONTAINER}:27017"
  docker run -d --name "$TARGET_CONTAINER" "${run_net[@]}" "$MONGO_IMAGE" >/dev/null
fi
# Connection strings never go on a command line or into a container's environment: they are
# written (shell builtin printf) to a private temp dir that is mounted read-only into each
# throwaway tool container and removed on exit.
cfg_dir=$(umask 077 && mktemp -d)
trap 'rm -rf "$cfg_dir"' EXIT
(
  umask 077
  printf 'uri: "%s"\n' "$SOURCE_MONGO_URI" > "$cfg_dir/source.yaml"
  printf 'uri: "%s"\n' "$target_uri" > "$cfg_dir/target.yaml"
  printf '%s' "$SOURCE_MONGO_URI" > "$cfg_dir/source.uri"
  printf '%s' "$target_uri" > "$cfg_dir/target.uri"
)

# The private mount is readable by the invoking host user. Rootful Docker: run the tools as
# that uid. Rootless Docker: container root already maps to that user.
if docker info --format '{{json .SecurityOptions}}' | grep -q rootless; then
  tool_user=()
else
  tool_user=(--user "$(id -u):$(id -g)")
fi

mongo_tool() {
  docker run --rm -i "${run_net[@]}" "${tool_user[@]}" -e HOME=/tmp -v "$cfg_dir:/cfg:ro" "$MONGO_IMAGE" "$@"
}

ping_script='const c = connect(require("fs").readFileSync("/cfg/target.uri", "utf8")); print(c.adminCommand({ ping: 1 }).ok)'

count_script='
const conn = connect(require("fs").readFileSync("/cfg/" + SIDE + ".uri", "utf8"));
const dbs = conn.adminCommand({ listDatabases: 1 }).databases
  .map(d => d.name)
  .filter(n => !["admin", "config", "local"].includes(n));
const out = [];
for (const name of dbs) {
  const d = conn.getSiblingDB(name);
  for (const c of d.getCollectionNames().sort()) {
    out.push(name + "." + c + " " + d.getCollection(c).countDocuments({}));
  }
}
print(out.join("\n"));
'

echo "waiting for target MongoDB"
for _ in $(seq 1 30); do
  if mongo_tool mongosh --nodb --quiet --eval "$ping_script" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "dumping source and restoring into $TARGET_CONTAINER"
mongo_tool mongodump --config=/cfg/source.yaml --archive --gzip --quiet \
  | mongo_tool mongorestore --config=/cfg/target.yaml --archive --gzip --drop --quiet

source_counts=$(mongo_tool mongosh --nodb --quiet --eval "const SIDE = 'source'; $count_script" | sort)
target_counts=$(mongo_tool mongosh --nodb --quiet --eval "const SIDE = 'target'; $count_script" | sort)

printf '%-40s %10s %10s\n' collection source target
join -a1 -a2 -e missing -o 0,1.2,2.2 <(echo "$source_counts") <(echo "$target_counts") \
  | while read -r coll src tgt; do printf '%-40s %10s %10s\n' "$coll" "$src" "$tgt"; done

if [ -n "$source_counts" ] && [ "$source_counts" = "$target_counts" ]; then
  echo "result: match"
else
  echo "result: mismatch"
  exit 2
fi
