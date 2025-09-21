# ========================
# Stage 0: Base image
# ========================
FROM oven/bun:alpine AS base
WORKDIR /app
ENV NODE_ENV=production

# ========================
# Stage 1: Install dependencies
# ========================
FROM base AS deps
WORKDIR /app
COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile

# ========================
# Stage 2: Build the application
# ========================
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN bun run build

# ========================
# Stage 3: Production server
# ========================
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production

# Copy built Next.js app
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# ✅ Copy node_modules from builder (includes drizzle-orm & drizzle-kit)
COPY --from=builder /app/node_modules ./node_modules

# ✅ Copy Drizzle config & schema for migrations
COPY --from=builder /app/drizzle.config.ts ./
COPY --from=builder /app/app/db ./app/db

# ✅ Copy Bun lockfile to ensure proper resolution
COPY --from=builder /app/bun.lockb ./

EXPOSE 3000

# ✅ Run migrations automatically, then start the server
CMD ["sh", "-c", "bun x drizzle-kit push --config ./drizzle.config.ts && bun run server.js"]
