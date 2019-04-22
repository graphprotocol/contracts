# Contracts

## Graph Protocol Contracts
![Restricted Calls Between Contracts](https://www.lucidchart.com/publicSegments/view/7b2d4166-1085-447f-bfb9-f2640e19794c/image.jpeg)

![Open Calls and Their Initiators](https://www.lucidchart.com/publicSegments/view/36fcf559-ab1f-42c9-bbb2-01f78274698e/image.jpeg)

### Graph Governance Contract ([Governed.sol](./Governed.sol))
For now, the Governance contract, owned by the multisig, will serve as the DAO. Later we will have a DAO contract that manages voting and consensus on governance matters.
- A multi-sig contract "governs" (owns) all upgradable contracts by inheriting the Governance contract and setting the `governor` in the upgradable contract's constructor.
- Upgrades all upgradable Graph smart contracts
- Sets all parameters which are allowed to be set via governance
- Can be irreversibly replaced or upgraded on its own authority (i.e. can replace itself).

### Graph Token Contract ([GraphToken.sol](./GraphToken.sol))
- Implements ERC-20 token standards with "Detailed", "Mintable", and "Burnable" standards.
- Has approved `treasurers` with permission to mint the token (i.e. Payment Channel Hub and Rewards Manager).
- Has a `governor` which can set `treasurers`, upgrade contract and set any parameters controlled via governance.

### Staking & Dispute Resolution Manager Contract ([Staking.sol](./Staking.sol))
- Indexing Nodes stake Graph Tokens to participate in the data retrieval market for a specific subgraph, as identified by `subgraphId` .
- Curators stake Graph Tokens to participate in a specific curation market, as identified by `subgraphId`
- For a stakingAmount to be considered valid, it must meet the following requirements:
    - `stakingAmount >= minimumStakingAmount` where `minimumStakingAmount` is set via governance.
    - The `stakingAmount` must be in the set of the top N staking amounts, where N is determined by the `maxIndexers` parameter which is set via governance.
    - Market Curators and Indexing Nodes will have separate `minimumStakingAmount`s defined as `minimumCurationStakingamount` and `minimumIndexingStakingAmount`.
- Has permission to slash balances in Staking Contract
- Has a centralized arbitrator that decides disputes
- Disputes require a deposit to create, equivalent to the amount that may be slashed.
- In successful dispute, 50% (or some other amount set through governance), of slashing amount goes to Fisherman, the rest goes to Graph DAO (where they are possibly burned).

### Rewards Manager ([RewardsManager.sol](./RewardsManager.sol))
- Has the ability to mint tokens according to the reward rules specified in mechanism design of technical specification.
- The ability to grant rewards may need to be splittable across multiple transactions and transaction originators for gas reasons.
- (Maybe) can mint tokens to reward whichever user assumes the cost of paying transaction fees for minting the rewards.

### Graph Name Service (GNS) Registry ([GNS.sol](./GNS.sol))
- Maps names to `subgraphId`
- Namespace owners control names within a namespace
- Top-level registrar assigns names to Ethereum Addresses
- Mapping a name to a `subgraphId` also requires curating that `subgraphId`.
- No contracts depend on the GNS Registry, but rather is consumed by users of The Graph.

### Service Registry ([ServiceRegistry.sol](./ServiceRegistry.sol))
- Maps Ethereum Addresses to URLs
- No other contracts depend on this, rather is consumed by users of The Graph.


## Supporting Contracts &amp; Libraries
1. ### Gnosis MultiSigWallet Contract ([./MultiSigWallet.sol](./MultiSigWallet.sol))

1. ### Open Zeppelin ERC20 Token Contracts ([./openzeppelin](./openzeppelin))
    - Open source contracts and libraries imported from Open Zeppelin's Github repository ([/OpenZeppelin/openzeppelin-solidity](https://github.com/OpenZeppelin/openzeppelin-solidity))
    - Release `v2.1`
    - Using "Detailed", "Mintable", and "Burnable" standards.
    - Includes helper libraries like: `SafeMath`, `Roles`, & `MinterRole`

1. ### Bancor Bonding Curve Formulas ([./bancor](./contracts/bancor/))
    - Contains formulas used in calculating Stake <> Shares conversions based on a reserve ratio.

1. ### ConsenSys Solidity Bytes Utils Library ([../installed_contracts/bytes/](../installed_contracts/bytes/))
    - Utility Solidity library composed of basic operations for tightly packed bytes arrays
