FROM node:22-alpine AS deps
WORKDIR /app/webapp
RUN corepack enable
COPY webapp/package.json webapp/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

FROM node:22-alpine AS build
WORKDIR /app/webapp
RUN corepack enable
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/webapp/node_modules ./node_modules
COPY webapp/ ./
COPY backend/openapi/openapi.json /app/backend/openapi/openapi.json
ARG VITA_API_URL
ARG VITA_ENV=staging
ENV NEXT_PUBLIC_VITA_API_URL=$VITA_API_URL
ENV NEXT_PUBLIC_VITA_ENV=$VITA_ENV
RUN pnpm gen:api && pnpm build

FROM node:22-alpine AS runner
WORKDIR /app
ARG VITA_ENV=staging
ENV NODE_ENV=production \
    VITA_ENV=$VITA_ENV \
    NEXT_TELEMETRY_DISABLED=1 \
    HOSTNAME=0.0.0.0 \
    PORT=3000
RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs
COPY --from=build --chown=nextjs:nodejs /app/webapp/public ./public
COPY --from=build --chown=nextjs:nodejs /app/webapp/.next/standalone ./
COPY --from=build --chown=nextjs:nodejs /app/webapp/.next/static ./.next/static
USER nextjs
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:3000/ || exit 1
CMD ["node", "server.js"]
