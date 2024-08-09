#
ARG NODE_VERSION=20.9.0

# Alpine image
FROM node:${NODE_VERSION}-alpine AS alpine
RUN apk update
RUN apk add --no-cache libc6-compat

# Setup pnpm and turbo on the alpine base
FROM alpine as base
RUN npm install pnpm turbo --global
RUN pnpm config set store-dir ~/.pnpm-store

# Prune projects
FROM base AS pruner
ARG PROJECT

WORKDIR /app
COPY . .
RUN turbo prune --scope=${PROJECT} --docker

# Build the project
FROM base AS builder
ARG PROJECT

WORKDIR /app

# Copy lockfile and package.json's of isolated subworkspace
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=pruner /app/out/pnpm-workspace.yaml ./pnpm-workspace.yaml
COPY --from=pruner /app/out/json/ .

# First install the dependencies (as they change less often)
RUN --mount=type=cache,id=pnpm,target=~/.pnpm-store pnpm install --frozen-lockfile

# Copy source code of isolated subworkspace
COPY --from=pruner /app/out/full/ .

RUN turbo build --filter=${PROJECT}
RUN --mount=type=cache,id=pnpm,target=~/.pnpm-store pnpm prune --prod --no-optional
RUN rm -rf ./**/*/src

# Node runner
FROM alpine AS node
ARG PROJECT

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs
USER nodejs

WORKDIR /app
COPY --from=builder --chown=nodejs:nodejs /app .
WORKDIR /app/apps/${PROJECT}

ARG COMMAND=dist/main
ENV COMMAND ${COMMAND}

ARG PORT=8080
ENV PORT=${PORT}
ENV NODE_ENV=production
EXPOSE ${PORT}

CMD node dist/main


# Next runner
FROM alpine AS next
ARG PROJECT

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

WORKDIR /app

RUN mkdir .next
RUN chown nextjs:nodejs .next

COPY --from=builder --chown=nextjs:nodejs /app/apps/${PROJECT}/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/${PROJECT}/.next/static ./apps/web/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/apps/${PROJECT}/public ./apps/web/public

USER nextjs

ARG PORT=8080
ENV PORT=${PORT}
EXPOSE ${PORT}
ENV NODE_ENV=production

CMD HOSTNAME="0.0.0.0" node apps/web/server.js

