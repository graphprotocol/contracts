# Contracts

## Graph Protocol Contracts
### Graph DAO Contract ([Governance.sol](./Governance.sol))
For now, the Governance contract, owned by the multisig, will serve as the DAO. Later we will have a DAO contract that manages voting and consensus on governance matters.
- A multi-sig contract owns the Governance contract and all upgradable contracts
- Upgrades all upgradable Graph smart contracts
- Sets all parameters which are allowed to be set via governance
- Can be irreversibly replaced or upgraded on its own authority (i.e. can replace itself).

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

### Graph Name Service (GNS) Registry ([GNS.sol](./GNS.sol))
- Maps names to `subgraphId`
- Namespace owners control names within a namespace
- Top-level registrar assigns names to Ethereum Addresses
- Mapping a name to a `subgraphId` also requires curating that `subgraphId`.
- No contracts depend on the GNS Registry, but rather is consumed by users of The Graph.

### Reward Manager ([RewardManager.sol](./RewardManager.sol))
- Has the ability to mint tokens according to the reward rules specified in mechanism design of technical specification.
- The ability to grant rewards may need to be splittable across multiple transactions and transaction originators for gas reasons.
- (Maybe) can mint tokens to reward whichever user assumes the cost of paying transaction fees for minting the rewards.

### Dispute Resolution Manager ([DisputeManager.sol](./DisputeManager.sol))
- Has permission to slash balances in Staking Contract
- Has a centralized arbitrator that decides disputes
- Disputes require a deposit to create, equivalent to the amount that may be slashed.
- In successful dispute, 50% (or some other amount set through governance), of slashing amount goes to Fisherman, the rest goes to Graph DAO (where they are possibly burned).


## (WIP...)

## Supporting Contracts &amp; Libraries
### Ownable ([Ownable.sol](./Ownable.sol))
- Owned contract from The Ethereum Wiki - ERC20 Token Standard

### BuranableERC20Token ([BurnableERC20Token.sol](./BurnableERC20Token.sol))
- Custom implimentation of the ERC20 Token Standard with burnable property added