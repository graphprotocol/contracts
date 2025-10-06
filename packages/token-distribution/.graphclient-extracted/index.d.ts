import { GraphQLResolveInfo, SelectionSetNode, FieldNode, GraphQLScalarType, GraphQLScalarTypeConfig } from 'graphql';
import { TypedDocumentNode as DocumentNode } from '@graphql-typed-document-node/core';
import type { GetMeshOptions } from '@graphql-mesh/runtime';
import type { YamlConfig } from '@graphql-mesh/types';
import { MeshHTTPHandler } from '@graphql-mesh/http';
import { ExecuteMeshFn, SubscribeMeshFn, MeshContext as BaseMeshContext, MeshInstance } from '@graphql-mesh/runtime';
import type { GraphNetworkTypes } from './sources/graph-network/types';
import type { TokenDistributionTypes } from './sources/token-distribution/types';
export type Maybe<T> = T | null;
export type InputMaybe<T> = Maybe<T>;
export type Scalars = {
    ID: string;
    String: string;
    Boolean: boolean;
    Int: number;
    Float: number;
    BigDecimal: any;
    BigInt: any;
    Bytes: any;
    Int8: any;
    Timestamp: any;
};
export type TokenLockWallet = {
    /** The address of the token lock wallet */
    id: Scalars['ID'];
    /** The Manager address */
    manager: Scalars['Bytes'];
    /** The hash of the initializer */
    initHash: Scalars['Bytes'];
    /** Address of the beneficiary of locked tokens */
    beneficiary: Scalars['Bytes'];
    /** The token being used (GRT) */
    token: Scalars['Bytes'];
    /** Amount of tokens to be managed by the lock contract */
    managedAmount: Scalars['BigInt'];
    /** Start time of the release schedule */
    startTime: Scalars['BigInt'];
    /** End time of the release schedule */
    endTime: Scalars['BigInt'];
    /** Number of periods between start time and end time */
    periods: Scalars['BigInt'];
    /** Time when the releases start */
    releaseStartTime: Scalars['BigInt'];
    /** Time the cliff vests, 0 if no cliff */
    vestingCliffTime: Scalars['BigInt'];
    /** Whether or not the contract is revocable */
    revocable?: Maybe<Revocability>;
    /** True if the beneficiary has approved addresses that the manager has approved */
    tokenDestinationsApproved: Scalars['Boolean'];
    /** The amount of tokens that have been resleased */
    tokensReleased: Scalars['BigInt'];
    /** The amount of tokens that have been withdrawn */
    tokensWithdrawn: Scalars['BigInt'];
    /** The amount of tokens that have been revoked */
    tokensRevoked: Scalars['BigInt'];
    /** The block this wlalet was created */
    blockNumberCreated: Scalars['BigInt'];
    /** The creation tx hash of the wallet */
    txHash: Scalars['Bytes'];
    /** ETH balance for L2 transfer. */
    ethBalance: Scalars['BigInt'];
    /** Tokens sent to L2 */
    tokensTransferredToL2: Scalars['BigInt'];
    /** Whether the vesting contract has experienced a transfer to L2 */
    transferredToL2: Scalars['Boolean'];
    /** Timestamp for the L1 -> L2 Transfer. */
    firstTransferredToL2At?: Maybe<Scalars['BigInt']>;
    /** Block number for the L1 -> L2 Transfer. */
    firstTransferredToL2AtBlockNumber?: Maybe<Scalars['BigInt']>;
    /** Transaction hash for the L1 -> L2 Transfer. */
    firstTransferredToL2AtTx?: Maybe<Scalars['String']>;
    /** Timestamp for the L1 -> L2 Transfer. */
    lastTransferredToL2At?: Maybe<Scalars['BigInt']>;
    /** Block number for the L1 -> L2 Transfer. */
    lastTransferredToL2AtBlockNumber?: Maybe<Scalars['BigInt']>;
    /** Transaction hash for the L1 -> L2 Transfer. */
    lastTransferredToL2AtTx?: Maybe<Scalars['String']>;
    /** Wallet address set for L2 transfer */
    l2WalletAddress?: Maybe<Scalars['Bytes']>;
    /** L1 wallet address that triggered the creation for this wallet in L2. Only available if the L2 wallet was created through transfer */
    l1WalletAddress?: Maybe<Scalars['Bytes']>;
    /** Beneficiary set for L2 transfer. Only for locked tokens codepath, fully vested won't be setting this */
    l2Beneficiary?: Maybe<Scalars['Bytes']>;
    /** Whether the wallet is fully vested or not. Fully vested wallets will have an l2WalletAddress set that is not a TokenLockWallet, but rather a normal EOA, since they can withdraw the funds whenever they please */
    l2WalletIsTokenLock?: Maybe<Scalars['Boolean']>;
    /** Tokens sent to L1 */
    tokensTransferredToL1: Scalars['BigInt'];
    /** Whether the vesting contract has experienced a transfer to L1 */
    transferredToL1: Scalars['Boolean'];
    /** Timestamp for the L2 -> L1 Transfer of locked funds. */
    firstLockedFundsTransferredToL1At?: Maybe<Scalars['BigInt']>;
    /** Block number for the L2 -> L1 Transfer of locked funds. */
    firstLockedFundsTransferredToL1AtBlockNumber?: Maybe<Scalars['BigInt']>;
    /** Transaction hash for the L2 -> L1 Transfer of locked funds. */
    firstLockedFundsTransferredToL1AtTx?: Maybe<Scalars['String']>;
    /** Timestamp for the L2 -> L1 Transfer of locked funds. */
    lastLockedFundsTransferredToL1At?: Maybe<Scalars['BigInt']>;
    /** Block number for the L2 -> L1 Transfer of locked funds. */
    lastLockedFundsTransferredToL1AtBlockNumber?: Maybe<Scalars['BigInt']>;
    /** Transaction hash for the L2 -> L1 Transfer of locked funds. */
    lastLockedFundsTransferredToL1AtTx?: Maybe<Scalars['String']>;
    /** Tokens sent to L1 (First time) */
    firstLockedFundsTransferredToL1Amount: Scalars['BigInt'];
    /** Tokens sent to L1 (Last time) */
    lastLockedFundsTransferredToL1Amount: Scalars['BigInt'];
};
export type Curator = {
    /** Eth address of the Curator */
    id: Scalars['ID'];
    /** Time this curator was created */
    createdAt: Scalars['Int'];
    /** Graph account of this curator */
    account: GraphAccount;
    /** CUMULATIVE tokens signalled on all the subgraphs */
    totalSignalledTokens: Scalars['BigInt'];
    /** CUMULATIVE tokens unsignalled on all the subgraphs */
    totalUnsignalledTokens: Scalars['BigInt'];
    /** Subgraphs the curator is curating */
    signals: Array<Signal>;
    /** Default display name is the current default name. Used for filtered queries */
    defaultDisplayName?: Maybe<Scalars['String']>;
    /** CUMULATIVE tokens signalled on all names */
    totalNameSignalledTokens: Scalars['BigInt'];
    /** CUMULATIVE tokens unsignalled on all names */
    totalNameUnsignalledTokens: Scalars['BigInt'];
    /** CUMULATIVE withdrawn tokens from deprecated subgraphs */
    totalWithdrawnTokens: Scalars['BigInt'];
    /** Subgraphs the curator is curating */
    nameSignals: Array<NameSignal>;
    /** NOT IMPLEMENTED - Summation of realized rewards from all Signals */
    realizedRewards: Scalars['BigInt'];
    /** NOT IMPLEMENTED - Annualized rate of return on curator signal */
    annualizedReturn: Scalars['BigDecimal'];
    /** NOT IMPLEMENTED - Total return of the curator */
    totalReturn: Scalars['BigDecimal'];
    /** NOT IMPLEMENTED - Signaling efficiency of the curator */
    signalingEfficiency: Scalars['BigDecimal'];
    /** CURRENT summed name signal for all bonding curves */
    totalNameSignal: Scalars['BigDecimal'];
    /** Total curator cost basis of all shares of name pools purchased on all bonding curves */
    totalNameSignalAverageCostBasis: Scalars['BigDecimal'];
    /** totalNameSignalAverageCostBasis / totalNameSignal */
    totalAverageCostBasisPerNameSignal: Scalars['BigDecimal'];
    /** CURRENT summed signal for all bonding curves */
    totalSignal: Scalars['BigDecimal'];
    /** Total curator cost basis of all version signal shares purchased on all bonding curves. Includes those purchased through GNS name pools */
    totalSignalAverageCostBasis: Scalars['BigDecimal'];
    /** totalSignalAverageCostBasis / totalSignal */
    totalAverageCostBasisPerSignal: Scalars['BigDecimal'];
    /** Total amount of signals created by this user */
    signalCount: Scalars['Int'];
    /** Amount of active signals for this user */
    activeSignalCount: Scalars['Int'];
    /** Total amount of name signals created by this user */
    nameSignalCount: Scalars['Int'];
    /** Amount of active name signals for this user */
    activeNameSignalCount: Scalars['Int'];
    /** Total amount of name signals and signals created by this user. signalCount + nameSignalCount */
    combinedSignalCount: Scalars['Int'];
    /** Amount of active name signals and signals for this user. signalCount + nameSignalCount */
    activeCombinedSignalCount: Scalars['Int'];
};
export type Delegator = {
    /** Delegator address */
    id: Scalars['ID'];
    /** Graph account of the delegator */
    account: GraphAccount;
    /** Stakes of this delegator */
    stakes: Array<DelegatedStake>;
    /** CUMULATIVE staked tokens in DelegatorStakes of this Delegator */
    totalStakedTokens: Scalars['BigInt'];
    /** CUMULATIVE unstaked tokens in DelegatorStakes of this Delegator */
    totalUnstakedTokens: Scalars['BigInt'];
    /** Time created at */
    createdAt: Scalars['Int'];
    /** Total realized rewards on all delegated stakes. Realized rewards are added when undelegating and realizing a profit */
    totalRealizedRewards: Scalars['BigDecimal'];
    /** Total DelegatedStake entity count (Active and inactive) */
    stakesCount: Scalars['Int'];
    /** Active DelegatedStake entity count. Active means it still has GRT delegated */
    activeStakesCount: Scalars['Int'];
    /** Default display name is the current default name. Used for filtered queries */
    defaultDisplayName?: Maybe<Scalars['String']>;
};
export type GraphAccount = {
    /** Graph account ID */
    id: Scalars['ID'];
    /** All names this graph account has claimed from all name systems */
    names: Array<GraphAccountName>;
    /** Default name the graph account has chosen */
    defaultName?: Maybe<GraphAccountName>;
    /** Time the account was created */
    createdAt: Scalars['Int'];
    /** Default display name is the current default name. Used for filtered queries in the explorer */
    defaultDisplayName?: Maybe<Scalars['String']>;
    metadata?: Maybe<GraphAccountMeta>;
    /** Operator of other Graph Accounts */
    operatorOf: Array<GraphAccount>;
    /** Operators of this Graph Accounts */
    operators: Array<GraphAccount>;
    /** Graph token balance */
    balance: Scalars['BigInt'];
    /** Balance received due to failed signal transfer from L1 */
    balanceReceivedFromL1Signalling: Scalars['BigInt'];
    /** Balance received due to failed delegation transfer from L1 */
    balanceReceivedFromL1Delegation: Scalars['BigInt'];
    /** Amount this account has approved staking to transfer their GRT */
    curationApproval: Scalars['BigInt'];
    /** Amount this account has approved curation to transfer their GRT */
    stakingApproval: Scalars['BigInt'];
    /** Amount this account has approved the GNS to transfer their GRT */
    gnsApproval: Scalars['BigInt'];
    /** Subgraphs the graph account owns */
    subgraphs: Array<Subgraph>;
    /** Time that this graph account became a developer */
    developerCreatedAt?: Maybe<Scalars['Int']>;
    /** NOT IMPLEMENTED - Total query fees the subgraphs created by this account have accumulated in GRT */
    subgraphQueryFees: Scalars['BigInt'];
    /** Disputes this graph account has created */
    createdDisputes: Array<Dispute>;
    /** Disputes against this graph account */
    disputesAgainst: Array<Dispute>;
    /** Curator fields for this GraphAccount. Null if never curated */
    curator?: Maybe<Curator>;
    /** Indexer fields for this GraphAccount. Null if never indexed */
    indexer?: Maybe<Indexer>;
    /** Delegator fields for this GraphAccount. Null if never delegated */
    delegator?: Maybe<Delegator>;
    /** Name signal transactions created by this GraphAccount */
    nameSignalTransactions: Array<NameSignalTransaction>;
    bridgeWithdrawalTransactions: Array<BridgeWithdrawalTransaction>;
    bridgeDepositTransactions: Array<BridgeDepositTransaction>;
    tokenLockWallets: Array<TokenLockWallet>;
};
export type GraphNetwork = {
    /** ID is set to 1 */
    id: Scalars['ID'];
    /** Controller address */
    controller: Scalars['Bytes'];
    /** Graph token address */
    graphToken: Scalars['Bytes'];
    /** Epoch manager address */
    epochManager: Scalars['Bytes'];
    /** Epoch Manager implementations. Last in the array is current */
    epochManagerImplementations: Array<Scalars['Bytes']>;
    /** Curation address */
    curation: Scalars['Bytes'];
    /** Curation implementations. Last in the array is current */
    curationImplementations: Array<Scalars['Bytes']>;
    /** Staking address */
    staking: Scalars['Bytes'];
    /** Graph token implementations. Last in the array is current */
    stakingImplementations: Array<Scalars['Bytes']>;
    /** Dispute manager address */
    disputeManager: Scalars['Bytes'];
    /** GNS address */
    gns: Scalars['Bytes'];
    /** Service registry address */
    serviceRegistry: Scalars['Bytes'];
    /** Rewards manager address */
    rewardsManager: Scalars['Bytes'];
    /** Rewards Manager implementations. Last in the array is current */
    rewardsManagerImplementations: Array<Scalars['Bytes']>;
    /** True if the protocol is paused */
    isPaused: Scalars['Boolean'];
    /** True if the protocol is partially paused */
    isPartialPaused: Scalars['Boolean'];
    /** Governor of the controller (i.e. the whole protocol) */
    governor: Scalars['Bytes'];
    /** Pause guardian address */
    pauseGuardian: Scalars['Bytes'];
    /** Percentage of fees going to curators. In parts per million */
    curationPercentage: Scalars['Int'];
    /** Percentage of fees burn as protocol fee. In parts per million */
    protocolFeePercentage: Scalars['Int'];
    /** Ratio of max staked delegation tokens to indexers stake that earns rewards */
    delegationRatio: Scalars['Int'];
    /** [DEPRECATED] Epochs to wait before fees can be claimed in rebate pool */
    channelDisputeEpochs: Scalars['Int'];
    /** Epochs to wait before delegators can settle */
    maxAllocationEpochs: Scalars['Int'];
    /** Time in blocks needed to wait to unstake */
    thawingPeriod: Scalars['Int'];
    /** Minimum time an Indexer must use for resetting their Delegation parameters */
    delegationParametersCooldown: Scalars['Int'];
    /** Minimum GRT an indexer must stake */
    minimumIndexerStake: Scalars['BigInt'];
    /** Contracts that have been approved to be a slasher */
    slashers?: Maybe<Array<Scalars['Bytes']>>;
    /** Time in epochs a delegator needs to wait to withdraw delegated stake */
    delegationUnbondingPeriod: Scalars['Int'];
    /** [DEPRECATED] Alpha in the cobbs douglas formula */
    rebateRatio: Scalars['BigDecimal'];
    /** Alpha in the exponential formula */
    rebateAlpha: Scalars['BigDecimal'];
    /** Lambda in the exponential formula */
    rebateLambda: Scalars['BigDecimal'];
    /** Tax that delegators pay to deposit. In Parts per million */
    delegationTaxPercentage: Scalars['Int'];
    /** Asset holder for the protocol */
    assetHolders?: Maybe<Array<Scalars['Bytes']>>;
    /** Total amount of indexer stake transferred to L2 */
    totalTokensStakedTransferredToL2: Scalars['BigInt'];
    /** Total amount of delegated tokens transferred to L2 */
    totalDelegatedTokensTransferredToL2: Scalars['BigInt'];
    /** Total amount of delegated tokens transferred to L2 */
    totalSignalledTokensTransferredToL2: Scalars['BigInt'];
    /** The total amount of GRT staked in the staking contract */
    totalTokensStaked: Scalars['BigInt'];
    /** NOT IMPLEMENTED - Total tokens that are settled and waiting to be claimed */
    totalTokensClaimable: Scalars['BigInt'];
    /** Total tokens that are currently locked or withdrawable in the network from unstaking */
    totalUnstakedTokensLocked: Scalars['BigInt'];
    /** Total GRT currently in allocation */
    totalTokensAllocated: Scalars['BigInt'];
    /** Total delegated tokens in the protocol */
    totalDelegatedTokens: Scalars['BigInt'];
    /** The total amount of GRT signalled in the Curation contract */
    totalTokensSignalled: Scalars['BigInt'];
    /** Total GRT currently curating via the Auto-Migrate function */
    totalTokensSignalledAutoMigrate: Scalars['BigDecimal'];
    /** Total GRT currently curating to a specific version */
    totalTokensSignalledDirectly: Scalars['BigDecimal'];
    /** Total query fees generated in the network */
    totalQueryFees: Scalars['BigInt'];
    /** Total query fees collected by indexers */
    totalIndexerQueryFeesCollected: Scalars['BigInt'];
    /** Total query fees rebates claimed by indexers */
    totalIndexerQueryFeeRebates: Scalars['BigInt'];
    /** Total query fees rebates claimed by delegators */
    totalDelegatorQueryFeeRebates: Scalars['BigInt'];
    /** Total query fees payed to curators */
    totalCuratorQueryFees: Scalars['BigInt'];
    /** Total protocol taxes applied to the query fees */
    totalTaxedQueryFees: Scalars['BigInt'];
    /** Total unclaimed rebates. Includes unclaimed rebates, and rebates lost in rebates mechanism  */
    totalUnclaimedQueryFeeRebates: Scalars['BigInt'];
    /** Total indexing rewards minted */
    totalIndexingRewards: Scalars['BigInt'];
    /** Total indexing rewards minted to Delegators */
    totalIndexingDelegatorRewards: Scalars['BigInt'];
    /** Total indexing rewards minted to Indexers */
    totalIndexingIndexerRewards: Scalars['BigInt'];
    /** (Deprecated) The issuance rate of GRT per block before GIP-0037. To get annual rate do (networkGRTIssuance * 10^-18)^(blocksPerYear) */
    networkGRTIssuance: Scalars['BigInt'];
    /** The issuance rate of GRT per block after GIP-0037. To get annual rate do (networkGRTIssuancePerBlock * blocksPerYear) */
    networkGRTIssuancePerBlock: Scalars['BigInt'];
    /** Address of the availability oracle */
    subgraphAvailabilityOracle: Scalars['Bytes'];
    /** Default reserve ratio for all subgraphs. In parts per million */
    defaultReserveRatio: Scalars['Int'];
    /** Minimum amount of tokens needed to start curating */
    minimumCurationDeposit: Scalars['BigInt'];
    /** The fee charged when a curator withdraws signal. In parts per million */
    curationTaxPercentage: Scalars['Int'];
    /** Percentage of the GNS migration tax payed by the subgraph owner */
    ownerTaxPercentage: Scalars['Int'];
    /** Graph Token supply */
    totalSupply: Scalars['BigInt'];
    /** NOT IMPLEMENTED - Price of one GRT in USD */
    GRTinUSD: Scalars['BigDecimal'];
    /** NOT IMPLEMENTED - Price of one GRT in ETH */
    GRTinETH?: Maybe<Scalars['BigDecimal']>;
    /** Total amount of GRT minted */
    totalGRTMinted: Scalars['BigInt'];
    /** Total amount of GRT burned */
    totalGRTBurned: Scalars['BigInt'];
    /** Epoch Length in blocks */
    epochLength: Scalars['Int'];
    /** Epoch that was last run */
    lastRunEpoch: Scalars['Int'];
    /** Epoch when epoch length was last updated */
    lastLengthUpdateEpoch: Scalars['Int'];
    /** Block when epoch length was last updated */
    lastLengthUpdateBlock: Scalars['Int'];
    /** Current epoch the protocol is in */
    currentEpoch: Scalars['Int'];
    /** Total indexers */
    indexerCount: Scalars['Int'];
    /** Number of indexers that currently have some stake in the protocol */
    stakedIndexersCount: Scalars['Int'];
    /** Total amount of delegators historically */
    delegatorCount: Scalars['Int'];
    /** Total active delegators. Those that still have at least one active delegation. */
    activeDelegatorCount: Scalars['Int'];
    /** Total amount of delegations historically */
    delegationCount: Scalars['Int'];
    /** Total active delegations. Those delegations that still have GRT staked towards an indexer */
    activeDelegationCount: Scalars['Int'];
    /** Total amount of curators historically */
    curatorCount: Scalars['Int'];
    /** Total amount of curators historically */
    activeCuratorCount: Scalars['Int'];
    /** Total amount of Subgraph entities */
    subgraphCount: Scalars['Int'];
    /** Amount of active Subgraph entities */
    activeSubgraphCount: Scalars['Int'];
    /** Total amount of SubgraphDeployment entities */
    subgraphDeploymentCount: Scalars['Int'];
    /** Total epochs */
    epochCount: Scalars['Int'];
    /** Total amount of allocations opened */
    allocationCount: Scalars['Int'];
    /** Total amount of allocations currently active */
    activeAllocationCount: Scalars['Int'];
    /** Dispute arbitrator */
    arbitrator: Scalars['Bytes'];
    /** Penalty to Indexer on successful disputes for query disputes. In parts per million */
    querySlashingPercentage: Scalars['Int'];
    /** Penalty to Indexer on successful disputes for indexing disputes. In parts per million */
    indexingSlashingPercentage: Scalars['Int'];
    /** [DEPRECATED] Penalty to Indexer on successful disputes for indexing disputes. In parts per million */
    slashingPercentage: Scalars['Int'];
    /** Minimum deposit to create a dispute */
    minimumDisputeDeposit: Scalars['BigInt'];
    /** Reward to Fisherman on successful disputes. In parts per million */
    fishermanRewardPercentage: Scalars['Int'];
    /** Total amount of GRT deposited to the L1 gateway. Note that the actual amount claimed in L2 might be lower due to tickets not redeemed. */
    totalGRTDeposited: Scalars['BigInt'];
    /** Total amount of GRT withdrawn from the L2 gateway and claimed in L1. */
    totalGRTWithdrawnConfirmed: Scalars['BigInt'];
    /** Total amount of GRT minted by L1 bridge */
    totalGRTMintedFromL2: Scalars['BigInt'];
    /** Total amount of GRT deposited to the L1 gateway and redeemed in L2. */
    totalGRTDepositedConfirmed: Scalars['BigInt'];
    /** Total amount of GRT withdrawn from the L2 gateway. Note that the actual amount claimed in L1 might be lower due to outbound transactions not finalized. */
    totalGRTWithdrawn: Scalars['BigInt'];
    /** Block number for L1. Only implemented for L2 deployments to properly reflect the L1 block used for timings */
    currentL1BlockNumber?: Maybe<Scalars['BigInt']>;
};
export type Indexer = {
    /** Eth address of Indexer */
    id: Scalars['ID'];
    /** Time this indexer was created */
    createdAt: Scalars['Int'];
    /** Graph account of this indexer */
    account: GraphAccount;
    /** Service registry URL for the indexer */
    url?: Maybe<Scalars['String']>;
    /** Geohash of the indexer. Shows where their indexer is located in the world */
    geoHash?: Maybe<Scalars['String']>;
    /** Default display name is the current default name. Used for filtered queries */
    defaultDisplayName?: Maybe<Scalars['String']>;
    /** CURRENT tokens staked in the protocol. Decreases on withdraw, not on lock */
    stakedTokens: Scalars['BigInt'];
    /** CURRENT  tokens allocated on all subgraphs */
    allocatedTokens: Scalars['BigInt'];
    /** NOT IMPLEMENTED - Tokens that have been unstaked and withdrawn */
    unstakedTokens: Scalars['BigInt'];
    /** CURRENT tokens locked */
    lockedTokens: Scalars['BigInt'];
    /** The block when the Indexers tokens unlock */
    tokensLockedUntil: Scalars['Int'];
    /** Active allocations of stake for this Indexer */
    allocations: Array<Allocation>;
    /** All allocations of stake for this Indexer (i.e. closed and active) */
    totalAllocations: Array<Allocation>;
    /** Number of active allocations of stake for this Indexer */
    allocationCount: Scalars['Int'];
    /** All allocations for this Indexer (i.e. closed and active) */
    totalAllocationCount: Scalars['BigInt'];
    /** Total query fees collected. Includes the portion given to delegators */
    queryFeesCollected: Scalars['BigInt'];
    /** Query fee rebate amount claimed from the protocol through rebates mechanism. Does not include portion given to delegators */
    queryFeeRebates: Scalars['BigInt'];
    /** Total indexing rewards earned by this indexer from inflation. Including delegation rewards */
    rewardsEarned: Scalars['BigInt'];
    /** The total amount of indexing rewards the indexer kept */
    indexerIndexingRewards: Scalars['BigInt'];
    /** The total amount of indexing rewards given to delegators */
    delegatorIndexingRewards: Scalars['BigInt'];
    /** Percentage of indexers' own rewards received in relation to its own stake. 1 (100%) means that the indexer is receiving the exact amount that is generated by his own stake */
    indexerRewardsOwnGenerationRatio: Scalars['BigDecimal'];
    /** Whether the indexer has been transferred from L1 to L2 partially or fully */
    transferredToL2: Scalars['Boolean'];
    /** Timestamp for the FIRST L1 -> L2 Transfer */
    firstTransferredToL2At?: Maybe<Scalars['BigInt']>;
    /** Block number for the FIRST L1 -> L2 Transfer */
    firstTransferredToL2AtBlockNumber?: Maybe<Scalars['BigInt']>;
    /** Transaction hash for the FIRST L1 -> L2 Transfer */
    firstTransferredToL2AtTx?: Maybe<Scalars['String']>;
    /** Timestamp for the latest L1 -> L2 Transfer */
    lastTransferredToL2At?: Maybe<Scalars['BigInt']>;
    /** Block number for the latest L1 -> L2 Transfer */
    lastTransferredToL2AtBlockNumber?: Maybe<Scalars['BigInt']>;
    /** Transaction hash for the latest L1 -> L2 Transfer */
    lastTransferredToL2AtTx?: Maybe<Scalars['String']>;
    /** Amount of GRT transferred to L2. Only visible from L1, as there's no events for it on L2 */
    stakedTokensTransferredToL2: Scalars['BigInt'];
    /** ID of the indexer on L2. Null if it's not transferred */
    idOnL2?: Maybe<Scalars['String']>;
    /** ID of the indexer on L1. Null if it's not transferred */
    idOnL1?: Maybe<Scalars['String']>;
    /** Amount of delegated tokens that can be eligible for rewards */
    delegatedCapacity: Scalars['BigInt'];
    /** Total token capacity = delegatedCapacity + stakedTokens */
    tokenCapacity: Scalars['BigInt'];
    /** Stake available to earn rewards. tokenCapacity - allocationTokens - lockedTokens */
    availableStake: Scalars['BigInt'];
    /** Delegators to this Indexer */
    delegators: Array<DelegatedStake>;
    /** CURRENT tokens delegated to the indexer */
    delegatedTokens: Scalars['BigInt'];
    /** Ratio between the amount of the indexers own stake over the total usable stake. */
    ownStakeRatio: Scalars['BigDecimal'];
    /** Ratio between the amount of delegated stake over the total usable stake. */
    delegatedStakeRatio: Scalars['BigDecimal'];
    /** Total shares of the delegator pool */
    delegatorShares: Scalars['BigInt'];
    /** Exchange rate of of tokens received for each share */
    delegationExchangeRate: Scalars['BigDecimal'];
    /** The percent of indexing rewards generated by the total stake that the Indexer keeps for itself. In parts per million */
    indexingRewardCut: Scalars['Int'];
    /** The percent of indexing rewards generated by the delegated stake that the Indexer keeps for itself */
    indexingRewardEffectiveCut: Scalars['BigDecimal'];
    /** The percent of reward dilution delegators experience because of overdelegation. Overdelegated stake can't be used to generate rewards but still gets accounted while distributing the generated rewards. This causes dilution of the rewards for the rest of the pool. */
    overDelegationDilution: Scalars['BigDecimal'];
    /** The total amount of query fees given to delegators */
    delegatorQueryFees: Scalars['BigInt'];
    /** The percent of query rebate rewards the Indexer keeps for itself. In parts per million */
    queryFeeCut: Scalars['Int'];
    /** The percent of query rebate rewards generated by the delegated stake that the Indexer keeps for itself */
    queryFeeEffectiveCut: Scalars['BigDecimal'];
    /** Amount of blocks a delegator chooses for the waiting period for changing their params */
    delegatorParameterCooldown: Scalars['Int'];
    /** Block number for the last time the delegator updated their parameters */
    lastDelegationParameterUpdate: Scalars['Int'];
    /** Count of how many times this indexer has been forced to close an allocation */
    forcedClosures: Scalars['Int'];
    /** NOT IMPLEMENTED - Total return this indexer has earned */
    totalReturn: Scalars['BigDecimal'];
    /** NOT IMPLEMENTED - Annualized rate of return for the indexer */
    annualizedReturn: Scalars['BigDecimal'];
    /** NOT IMPLEMENTED - Staking efficiency of the indexer */
    stakingEfficiency: Scalars['BigDecimal'];
};
export type GraphAccountQuery = {
    graphAccount?: Maybe<(Pick<GraphAccount, 'id'> & {
        indexer?: Maybe<Pick<Indexer, 'stakedTokens'>>;
        curator?: Maybe<Pick<Curator, 'totalSignalledTokens' | 'totalUnsignalledTokens'>>;
        delegator?: Maybe<Pick<Delegator, 'totalStakedTokens' | 'totalUnstakedTokens' | 'totalRealizedRewards'>>;
    })>;
};
export type CuratorWalletsQuery = {
    tokenLockWallets: Array<Pick<TokenLockWallet, 'id' | 'beneficiary' | 'managedAmount' | 'periods' | 'startTime' | 'endTime' | 'revocable' | 'releaseStartTime' | 'vestingCliffTime' | 'initHash' | 'txHash' | 'manager' | 'tokensReleased' | 'tokensWithdrawn' | 'tokensRevoked' | 'blockNumberCreated'>>;
};
export type GraphNetworkQuery = {
    graphNetwork?: Maybe<Pick<GraphNetwork, 'id' | 'totalSupply'>>;
};
export type TokenLockWalletsQuery = {
    tokenLockWallets: Array<Pick<TokenLockWallet, 'id' | 'beneficiary' | 'managedAmount' | 'periods' | 'startTime' | 'endTime' | 'revocable' | 'releaseStartTime' | 'vestingCliffTime' | 'initHash' | 'txHash' | 'manager' | 'tokensReleased' | 'tokensWithdrawn' | 'tokensRevoked' | 'blockNumberCreated'>>;
};