# Generic Vite/React frontend Dockerfile for sovereign modules.
# Used by users-fe, companies-fe, workspaces-fe, support-fe.
#
# Each module's source tree is expected at the build context root:
#   package.json
#   vite.config.js
#   index.html
#   src/main.jsx
#
# The container serves the built SPA on the PORT the env passes via `vite
# preview`. Compose owns the port mapping.

FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY . .

# Build-time env: Vite bakes VITE_* vars into the bundle. For local dev these
# come from the compose `environment:` block at build time.
ARG VITE_USERS_BE_URL
ARG VITE_COMPANIES_BE_URL
ARG VITE_WORKSPACES_BE_URL
ARG VITE_SUPPORT_BE_URL
ARG VITE_PORTAL_SHELL_URL
ARG VITE_USERS_FE_URL
ARG VITE_COMPANIES_FE_URL
ARG VITE_WORKSPACES_FE_URL

RUN npm run build

FROM node:20-alpine AS runtime
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
COPY --from=build --chown=app:app /app /app
USER app

ENV NODE_ENV=production
# `vite preview` serves the production build on the configured port.
CMD ["sh", "-c", "npx vite preview --host 0.0.0.0 --port ${PORT:-3000}"]
