# syntax=docker/dockerfile:1

FROM node:22-alpine AS ui-build
WORKDIR /ui
COPY ui/package.json ui/yarn.lock ./
RUN yarn install --frozen-lockfile --network-timeout 600000
COPY ui/ ./
# Empty API base URL: the bundle calls the API on the same origin that serves it.
ENV REACT_APP_expressDomain=""
RUN yarn build

FROM node:22-alpine AS api-deps
WORKDIR /api
COPY api/package.json api/yarn.lock ./
RUN yarn install --frozen-lockfile --production --network-timeout 600000 \
  && yarn cache clean

FROM node:22-alpine
ENV NODE_ENV=production \
    PORT=8080 \
    UI_BUILD_DIR=/app/public
WORKDIR /app
COPY --from=api-deps /api/node_modules ./node_modules
COPY api/package.json ./
COPY api/src ./src
COPY --from=ui-build /ui/build ./public
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -qO /dev/null http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "src/app.js"]
