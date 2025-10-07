"use strict";
Object.defineProperty(exports, "__esModule", { value: true });

// Minimal GraphClient for offline builds - contains only what ops/info.ts uses
// Simple gql template literal function (replacement for @graphql-mesh/utils)
const gql = (strings, ...values) => {
  let result = strings[0];
  for (let i = 0; i < values.length; i++) {
    result += values[i] + strings[i + 1];
  }
  return result;
};

// Mock execute function
const execute = () => {
  throw new Error('GraphClient execute() requires API key. This is an offline build with cached types only.');
};
exports.execute = execute;

// Only the query documents actually used
exports.GraphAccountDocument = gql`
    query GraphAccount($accountId: ID!, $blockNumber: Int) {
  graphAccount(id: $accountId, block: {number: $blockNumber}) {
    id
    indexer {
      stakedTokens
    }
    curator {
      totalSignalledTokens
      totalUnsignalledTokens
    }
    delegator {
      totalStakedTokens
      totalUnstakedTokens
      totalRealizedRewards
    }
  }
}
    `;

exports.CuratorWalletsDocument = gql`
    query CuratorWallets($blockNumber: Int, $first: Int) {
  tokenLockWallets(
    block: {number: $blockNumber}
    where: {periods: 16, startTime: 1608224400, endTime: 1734454800, revocable: Disabled}
    first: $first
    orderBy: blockNumberCreated
  ) {
    id
    beneficiary
    managedAmount
    periods
    startTime
    endTime
    revocable
    releaseStartTime
    vestingCliffTime
    initHash
    txHash
    manager
    tokensReleased
    tokensWithdrawn
    tokensRevoked
    blockNumberCreated
  }
}
    `;

exports.GraphNetworkDocument = gql`
    query GraphNetwork($blockNumber: Int) {
  graphNetwork(id: 1, block: {number: $blockNumber}) {
    id
    totalSupply
  }
}
    `;

exports.TokenLockWalletsDocument = gql`
    query TokenLockWallets($blockNumber: Int, $first: Int) {
  tokenLockWallets(block: {number: $blockNumber}, first: $first, orderBy: id) {
    id
    beneficiary
    managedAmount
    periods
    startTime
    endTime
    revocable
    releaseStartTime
    vestingCliffTime
    initHash
    txHash
    manager
    tokensReleased
    tokensWithdrawn
    tokensRevoked
    blockNumberCreated
  }
}
    `;

// Mock SDK
function getSdk() {
  return {
    GraphAccount: () => execute(),
    CuratorWallets: () => execute(),
    GraphNetwork: () => execute(),
    TokenLockWallets: () => execute(),
  };
}
exports.getSdk = getSdk;
