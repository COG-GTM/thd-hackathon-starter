# Migration map: hackathon-starter to the x86 Kubernetes platform

App migration wave. This file maps what the app runs on today and the target design.

## Runtime and package manager (today)

| Where | Node version | Notes |
|---|---|---|
| `.travis.yml` | `12.4.0` | Only pinned version; CI installs `jest@24.7.1` and `react-scripts@3.0.1` globally, runs `yarn test` and `yarn build` per package |
| `api/Dockerfile`, `api/dockerfile.dev`, `ui/dockerfile.dev` | `node:alpine` (unpinned, floats to the newest release) | |
| `ui/Dockerfile` | `nginx:1.15.2-alpine` | Serves a pre-built `ui/build` copied in from outside the image |
| README badge | 12.4.0 | |

- Package manager: Yarn 1 (`api/yarn.lock`, `ui/yarn.lock`). No `engines`, no `.nvmrc`.
- Two packages: `api/` (Express 4.15 + Mongoose 5.5 + Passport local) and `ui/` (create-react-app, `react-scripts` 3.0.1, React 16).

## Packages with a known break on Node 22

| Package | Version | Break on Node 22 | Plan |
|---|---|---|---|
| `react-scripts` (ui) | 3.0.1 | Webpack 4 hashes with MD4; OpenSSL 3 rejects it: `yarn build` fails with `ERR_OSSL_EVP_UNSUPPORTED` (reproduced) | Upgrade to `react-scripts` 5 (webpack 5). No `--openssl-legacy-provider` |
| `mongoose` (api) | 5.5.x (MongoDB driver 3.2) | None on Node 22; driver 3.x is end of life and logs deprecations (`ensureIndex`, `remove`). Tests pass against MongoDB 7.0 | Upgraded within major 5 to `^5.13.23` (driver 3.7) to clear the driver warnings; a move to Mongoose 8 is a later change |
| `jest` (api) | 24.x | None found; tests pass | Keep |
| `nodemon` (api) | 1.19.1, listed under `dependencies` | Dev-only watcher pulled into the production install (old `chokidar`/`fsevents`) | Move to `devDependencies`; production image runs `node src/app.js` |

## Datastores, caches, buckets, external APIs

- MongoDB via Mongoose (`api/src/db/bootstrap-mongoose.js`). Default URL `mongodb://mongo/my_database`. One model, `Account` (collection `accounts`, Passport local hash and salt fields).
- Sessions: `cookie-session` (signed client-side cookie). No server-side session store, so replicas are stateless if they share the signing key.
- Caches: none. Object storage / S3 buckets: none found in code, dependencies or config.
- External APIs at runtime: none. `recaptchaSecretKey` is templated into `api/app.yaml` but never read (captcha is a README TODO). Codecov is CI-only.

## Environment variables

| Variable | Read in | Purpose | Secret |
|---|---|---|---|
| `mongoUrl` | `api/src/db/bootstrap-mongoose.js` (`api/src/app.test.js` sets a test default) | MongoDB connection string | yes |
| `cookieSigningKey` | `api/src/app.js` | `cookie-session` signing key; falls back to a hard-coded `secretkey1` | yes |
| `NODE_ENV` | `api/startup.sh`, `api/src/app.js` | `production` runs `node`, otherwise `nodemon`; `test` skips `listen` | no |
| `PORT` | `api/src/app.js` | Listen port, default 3002 | no |
| `corsDomain` | `api/app.yaml` only | Not read by code; CORS allow-list is hard-coded in `app.js` | no |
| `recaptchaSecretKey` | `api/app.yaml` only | Not read by code | yes |
| `REACT_APP_expressDomain` | `ui/src/login/Login.js` (build time) | API base URL baked into the bundle, default `http://localhost:3002` | no |

## Ports

- Dev (`docker-compose.yml`): UI 3001 (CRA dev server), API 3002, Node inspector 56745, MongoDB 27017.
- Prod descriptors (`api/Dockerfile`, `ui/Dockerfile`, `app.yaml`): 8080 for both services.

## Build steps (today)

- UI: `yarn install`, `yarn build` (CRA) produces `ui/build`, which `ui/Dockerfile` copies into nginx.
- API: no compile step. `yarn build` in `api/` is a deploy-templating script, not a build (see below).
- CI: Travis matrix (`api`, `ui`): `yarn install`, `yarn test`, `codecov`, `yarn build`, with a Travis MongoDB service.

## How secrets get into the build today

`api/package.json` `build` runs `sed` over `api/app.yaml`, replacing `{{MONGO_URL}}`, `{{CORS_DOMAIN}}`, `{{COOKIE_SIGNING_KEY}}`, `{{RECAPTCHA_SECRET_KEY}}` with the values of shell variables `prodMongoUrl`, `corsDomain`, `cookieSigningKey`, `recaptchaSecretKey`. Secrets end up as plain text in the App Engine deploy descriptor, and `gae.json` (a deploy credential file) is git-ignored at the root. Nothing is injected at runtime.

## Gotchas found while mapping

- `api/startup.sh` uses `[ $NODE_ENV = "production" ]` unquoted; with `NODE_ENV` unset the test errors and falls through to `nodemon`.
- The CORS origin check uses `Array.filter` as a boolean, so every origin is allowed (with credentials). Not changed in this migration; flagged for the app owners.
- The API `GET /` returns `hello`; the UI's `/` and `/landing` are client-side routes.

## Target design

- **Compute moves**: one `linux/amd64` image built from a root multi-stage `Dockerfile` on Node 22 LTS. Stage 1 builds the UI (`react-scripts` 5); stage 2 installs API production dependencies; the runtime stage (`node:22-alpine`, non-root `USER node`) runs `node src/app.js` on port 8080 and serves the UI build from the same origin (`UI_BUILD_DIR`), so the bundle calls the API with relative URLs and there is no cross-origin cookie. `/healthz` (process up) and `/readyz` (MongoDB connected) back the probes. `helmet` sets security headers (default CSP, so the UI build emits its webpack runtime as a file: `INLINE_RUNTIME_CHUNK=false`).
- **Data moves** (network zone `internet`: the platform cannot reach the old network): MongoDB moves to a platform-provisioned instance from a Crossplane claim; the app reads `mongoUrl` from the claim's connection secret. `scripts/migrate-data.sh` dumps the source with `mongodump` and restores with `mongorestore`, then compares per-collection counts. No bucket to move.
- **Secrets**: `cookieSigningKey` and `mongoUrl` come from Kubernetes Secrets at runtime (references only in the infra repo); the `app.yaml` `sed` templating is no longer used by the platform path.
- **Network path**: public ingress (HTTP 8080 behind the platform ingress) to the app; app to the platform MongoDB on 27017 inside the cluster network. No other egress needed.
- **Stays**: existing `docker-compose.yml` dev loop, `api/Dockerfile`, `ui/Dockerfile` and `app.yaml` descriptors (base images moved to Node 22).
