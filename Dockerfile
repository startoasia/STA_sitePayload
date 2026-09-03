# Use Debian-slim for optimal compatibility with Sharp, Next.js, and native Node modules
FROM node:22-bookworm-slim AS base

WORKDIR /app

# Step 1: Install dependencies
FROM base AS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./

# Bypass strict CI/CD lockfile sync check and resolve any peer dependency conflicts
RUN npm install --legacy-peer-deps --no-audit

# Step 2: Build application
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Ensure public and media folders exist to prevent COPY instructions from failing
RUN mkdir -p /app/public /app/media

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Dummy secret for build-time Next.js static evaluation
ARG PAYLOAD_SECRET=build_time_payload_secret_key
ENV PAYLOAD_SECRET=$PAYLOAD_SECRET

RUN npm run build

# Step 3: Production runner image
FROM base AS runner
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Use non-root node user provided by official Debian node image
RUN mkdir -p /app/public /app/media /app/.next/cache && \
    chown -R node:node /app

# Copy built assets
COPY --from=builder /app/public ./public
COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static

USER node

EXPOSE 3000

CMD ["node", "server.js"]
