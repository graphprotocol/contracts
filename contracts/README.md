# Contracts

## Graph Protocol Contracts
### Graph DAO Contract ([Governance.sol](./Governance.sol))
- Multi-sig contract governance contract
- Upgrades all Graph smart contracts
- Sets all parameters which are set via governance
- Can be irreversibly replaced or upgraded on it's own authority (i.e. can replace itself).

### Graph Token Contract ([GraphToken.sol](./GraphToken.sol))
- Implements ERC-20 (and what else?)
- Has approved `treasurers` with permission to mint the token (i.e. Payment Channel Hub and Rewards Manager).
- Has `owner` which can set `treasurers`, upgrade contract and set any parameters controlled via governance.

### Staking Contract ([Staking.sol](./Staking.sol))
- Indexing Nodes stake Graph Tokens to participate in the data retrieval market for a specific subgraph, as identified by `subgraphId` .
- Curators stake Graph Tokens to participate in a specific curation market, as identified by `subgraphId`
- For a stakingAmount to be considered valid, it must meet the following requirements:
    - `stakingAmount >= minimumStakingAmount` where `minimumStakingAmount` is set via governance.
    - The `stakingAmount` must be in the set of the top N staking amounts, where N is determined by the `maxIndexers` parameter which is set via governance.
    - Market Curators and Indexing Nodes will have separate `minimumStakingAmount`s defined as `minimumCurationStakingamount` and `minimumIndexingStakingAmount`.

## (WIP...)

## Supporting Contracts &amp; Libraries
### Ownable ([Ownable.sol](./Ownable.sol))
- Owned contract from The Ethereum Wiki - ERC20 Token Standard

### BuranableERC20Token ([BurnableERC20Token.sol](./BurnableERC20Token.sol))
- Custom implimentation of the ERC20 Token Standard with burnable property added