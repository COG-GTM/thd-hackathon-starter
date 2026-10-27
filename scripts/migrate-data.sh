#!/usr/bin/env bash
# Copy the app's MongoDB database into a fresh MongoDB container and compare
# per-collection document counts between source and target.
#
# Required environment (passed by name, never echoed):
#   SOURCE_MONGO_URI   connection string of the source database
# Optional environment:
#   DOCKER_NETWORK     docker network that can reach the source (default: host)
#   TARGET_CONTAINER   name of the fresh target container (default: mongo-migration-target)
#   TARGET_PORT        host port for the target container (default: 27018)
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
  docker run -d --name "$TARGET_CONTAINER" -p "${TARGET_PORT}:27017" "$MONGO_IMAGE" >/dev/null
else
  target_uri="mongodb://${TARGET_CONTAINER}:27017"
  docker run -d --name "$TARGET_CONTAINER" "${run_net[@]}" -p "${TARGET_PORT}:27017" "$MONGO_IMAGE" >/dev/null
fi
export TARGET_MONGO_URI="$target_uri"

mongo_tool() {
  docker run --rm -i "${run_net[@]}" -e SOURCE_MONGO_URI -e TARGET_MONGO_URI "$MONGO_IMAGE" "$@"
}

echo "waiting for target MongoDB"
for _ in $(seq 1 30); do
  if mongo_tool sh -c 'mongosh "$TARGET_MONGO_URI" --quiet --eval "db.adminCommand({ping: 1}).ok"' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "dumping source and restoring into $TARGET_CONTAINER"
mongo_tool sh -c 'mongodump --uri="$SOURCE_MONGO_URI" --archive --gzip --quiet' \
  | mongo_tool sh -c 'mongorestore --uri="$TARGET_MONGO_URI" --archive --gzip --drop --quiet'

count_script='
const dbs = db.adminCommand({ listDatabases: 1 }).databases
  .map(d => d.name)
  .filter(n => !["admin", "config", "local"].includes(n));
const out = [];
for (const name of dbs) {
  const d = db.getSiblingDB(name);
  for (const c of d.getCollectionNames().sort()) {
    out.push(name + "." + c + " " + d.getCollection(c).countDocuments({}));
  }
}
print(out.join("\n"));
'

source_counts=$(mongo_tool sh -c 'mongosh "$SOURCE_MONGO_URI" --quiet --eval "$0"' "$count_script" | sort)
target_counts=$(mongo_tool sh -c 'mongosh "$TARGET_MONGO_URI" --quiet --eval "$0"' "$count_script" | sort)

printf '%-40s %10s %10s\n' collection source target
join -a1 -a2 -e missing -o 0,1.2,2.2 <(echo "$source_counts") <(echo "$target_counts") \
  | while read -r coll src tgt; do printf '%-40s %10s %10s\n' "$coll" "$src" "$tgt"; done

if [ -n "$source_counts" ] && [ "$source_counts" = "$target_counts" ]; then
  echo "result: match"
else
  echo "result: mismatch"
  exit 2
fi
