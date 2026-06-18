# Generic Node.js agent sidecar Dockerfile for sovereign modules.
# Used by support-agent (and any future module's agent sidecar).
#
# Agents differ from regular BEs in three ways:
#   1. No MongoDB connection (agents own no data — see anti-patterns §19)
#   2. Bonded to exactly one parent BE via PARENT_BE_URL
#   3. Authenticate to the parent with SERVICE_PRINCIPAL_SECRET, not a user JWT
#
# Each agent's source tree is expected at the build context root:
#   package.json
#   src/server.js

FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; \
    else npm install --omit=dev; fi

COPY . .

FROM node:20-alpine AS runtime
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
COPY --from=build --chown=app:app /app /app
USER app

ENV NODE_ENV=production
CMD ["node", "src/server.js"]
