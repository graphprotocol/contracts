default:
    @just --list

# Build the workspace image locally as `ghcr.io/graphprotocol/contracts:local`.
# Override the tag with `CONTRACTS_TAG=foo just build-image`. Consumed by
# local-network's graph-contracts wrapper when CONTRACTS_VERSION=local.
build-image:
    docker compose build
