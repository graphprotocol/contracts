# Workspace base image: deps + `pnpm install` + `pnpm build`, no entrypoint.
# Consumers (e.g. local-network's graph-contracts wrapper) layer their own
# deploy script on top, or `docker run` to invoke pnpm/hardhat directly.

FROM node:24-bookworm-slim

# libudev-dev / libusb-1.0-0-dev: native deps of hardhat-secure-accounts.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       curl git jq python3 make g++ libudev-dev libusb-1.0-0-dev \
  && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/foundry-rs/foundry:stable \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/

ENV COREPACK_ENABLE_STRICT=1
RUN corepack enable

# Husky's postinstall needs .git and is pointless in an image build.
ENV HUSKY=0

WORKDIR /opt/contracts

COPY . .

RUN pnpm install --frozen-lockfile \
  && pnpm build
