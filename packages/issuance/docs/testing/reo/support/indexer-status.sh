#!/bin/bash
# Query basic indexer status from the network subgraph.
#
# Usage:
#   ./indexer-status.sh <indexer-address> [mainnet]
#
# Environment:
#   GRAPH_API_KEY  Required. Your Graph API key.
#
# Examples:
#   GRAPH_API_KEY=abc123 ./indexer-status.sh 0xdeadbeef...
#   GRAPH_API_KEY=abc123 ./indexer-status.sh 0xdeadbeef... mainnet

set -euo pipefail

INDEXER=${1:-}
NETWORK=${2:-testnet}

if [[ -z "$INDEXER" ]]; then
  echo "Usage: $0 <indexer-address> [mainnet]" >&2
  exit 1
fi

if [[ -z "${GRAPH_API_KEY:-}" ]]; then
  echo "Error: GRAPH_API_KEY is not set" >&2
  exit 1
fi

# Addresses must be lowercase for the subgraph
INDEXER=$(echo "$INDEXER" | tr '[:upper:]' '[:lower:]')

if [[ "$NETWORK" == "mainnet" ]]; then
  SUBGRAPH_URL="https://gateway.thegraph.com/api/$GRAPH_API_KEY/subgraphs/id/DZz4kDTdmzWLWsV373w2bSmoar3umKKH9y82SUKr5qmp"
else
  SUBGRAPH_URL="https://gateway.thegraph.com/api/$GRAPH_API_KEY/subgraphs/id/3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV"
fi

QUERY=$(cat <<GQL
{
  indexers(where: { id: "$INDEXER" }) {
    id
    url
    geoHash
    stakedTokens
    allocatedTokens
    availableStake
    delegatedTokens
    queryFeeCut
    indexingRewardCut
    queryFeesCollected
    rewardsEarned
  }
  provisions(where: { indexer_: { id: "$INDEXER" } }) {
    dataService { id }
    tokensProvisioned
    tokensAllocated
    tokensThawing
  }
  allocations(where: { indexer_: { id: "$INDEXER" }, status: "Active" }) {
    id
    allocatedTokens
    createdAtEpoch
    subgraphDeployment { ipfsHash }
  }
  graphNetworks {
    currentEpoch
  }
}
GQL
)

curl -s "$SUBGRAPH_URL" \
  -H 'content-type: application/json' \
  -d "{\"query\": $(echo "$QUERY" | jq -Rs .)}" \
  | jq .
