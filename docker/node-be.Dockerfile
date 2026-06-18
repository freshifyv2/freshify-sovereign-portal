# Generic Node.js backend Dockerfile for sovereign modules.
# Used by users-be, companies-be, workspaces-be, support-be.
#
# Each module's source tree is expected at the build context root:
#   package.json
#   package-lock.json   (or pnpm-lock.yaml / yarn.lock)
#   src/server.js
#
# The container exposes whatever PORT the env passes; the compose file owns
# port mapping.

FROM node:20-alpine AS build
WORKDIR /app

# Install dependencies (cache layer)
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; \
    else npm install --omit=dev; fi

# Copy source
COPY . .

FROM node:20-alpine AS runtime
WORKDIR /app

# Run as non-root in the runtime image
RUN addgroup -S app && adduser -S app -G app
COPY --from=build --chown=app:app /app /app
USER app

ENV NODE_ENV=production
CMD ["node", "src/server.js"]
