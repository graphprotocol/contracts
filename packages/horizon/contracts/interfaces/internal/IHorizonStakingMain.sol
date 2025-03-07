// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";

/**
 * @title Inferface for the {HorizonStaking} contract.
 * @notice Provides functions for managing stake, provisions, delegations, and slashing.
 * @dev Note that this interface only includes the functions implemented by {HorizonStaking} contract,
 * and not those implemented by {HorizonStakingExtension}.
 * Do not use this interface to interface with the {HorizonStaking} contract, use {IHorizonStaking} for
 * the complete interface.
 * @dev Most functions operate over {HorizonStaking} provisions. To uniquely identify a provision
 * functions take `serviceProvider` and `verifier` addresses.
 * @dev TRANSITION PERIOD: After transition period rename to IHorizonStaking.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IHorizonStakingMain {
    // -- Events: stake --

    /**
     * @notice Emitted when a service provider unstakes tokens during the transition period.
     * @param serviceProvider The address of the service provider
     * @param tokens The amount of tokens unstaked
     * @param until The block number until the stake is locked
     */
    event HorizonStakeLocked(address indexed serviceProvider, uint256 tokens, uint256 until);

    /**
     * @notice Emitted when a service provider withdraws tokens during the transition period.
     * @param serviceProvider The address of the service provider
     * @param tokens The amount of tokens withdrawn
     */
    event HorizonStakeWithdrawn(address indexed serviceProvider, uint256 tokens);

    // -- Events: provision --

    /**
     * @notice Emitted when a service provider provisions staked tokens to a verifier.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens provisioned
     * @param maxVerifierCut The maximum cut, expressed in PPM of the slashed amount, that a verifier can take for themselves when slashing
     * @param thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    event ProvisionCreated(
        address indexed serviceProvider,
        address indexed verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    );

    /**
     * @notice Emitted whenever staked tokens are added to an existing provision
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens added to the provision
     */
    event ProvisionIncreased(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when a service provider thaws tokens from a provision.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens thawed
     */
    event ProvisionThawed(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when a service provider removes tokens from a provision.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens removed
     */
    event TokensDeprovisioned(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when a service provider stages a provision parameter update.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param maxVerifierCut The proposed maximum cut, expressed in PPM of the slashed amount, that a verifier can take for
     * themselves when slashing
     * @param thawingPeriod The proposed period in seconds that the tokens will be thawing before they can be removed from
     * the provision
     */
    event ProvisionParametersStaged(
        address indexed serviceProvider,
        address indexed verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    );

    /**
     * @notice Emitted when a service provider accepts a staged provision parameter update.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param maxVerifierCut The new maximum cut, expressed in PPM of the slashed amount, that a verifier can take for themselves
     * when slashing
     * @param thawingPeriod The new period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    event ProvisionParametersSet(
        address indexed serviceProvider,
        address indexed verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    );

    /**
     * @dev Emitted when an operator is allowed or denied by a service provider for a particular verifier
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param operator The address of the operator
     * @param allowed Whether the operator is allowed or denied
     */
    event OperatorSet(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed operator,
        bool allowed
    );

    // -- Events: slashing --

    /**
     * @notice Emitted when a provision is slashed by a verifier.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens slashed (note this only represents service provider's slashed stake)
     */
    event ProvisionSlashed(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when a delegation pool is slashed by a verifier.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens slashed (note this only represents delegation pool's slashed stake)
     */
    event DelegationSlashed(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when a delegation pool would have been slashed by a verifier, but the slashing was skipped
     * because delegation slashing global parameter is not enabled.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens that would have been slashed (note this only represents delegation pool's slashed stake)
     */
    event DelegationSlashingSkipped(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when the verifier cut is sent to the verifier after slashing a provision.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param destination The address where the verifier cut is sent
     * @param tokens The amount of tokens sent to the verifier
     */
    event VerifierTokensSent(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed destination,
        uint256 tokens
    );

    // -- Events: delegation --

    /**
     * @notice Emitted when tokens are delegated to a provision.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param delegator The address of the delegator
     * @param tokens The amount of tokens delegated
     * @param shares The amount of shares delegated
     */
    event TokensDelegated(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed delegator,
        uint256 tokens,
        uint256 shares
    );

    /**
     * @notice Emitted when a delegator undelegates tokens from a provision and starts
     * thawing them.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param delegator The address of the delegator
     * @param tokens The amount of tokens undelegated
     * @param tokens The amount of shares undelegated
     */
    event TokensUndelegated(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed delegator,
        uint256 tokens,
        uint256 shares
    );

    /**
     * @notice Emitted when a delegator withdraws tokens from a provision after thawing.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param delegator The address of the delegator
     * @param tokens The amount of tokens withdrawn
     */
    event DelegatedTokensWithdrawn(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed delegator,
        uint256 tokens
    );

    /**
     * @notice Emitted when `delegator` withdrew delegated `tokens` from `indexer` using `withdrawDelegated`.
     * @dev This event is for the legacy `withdrawDelegated` function.
     * @param indexer The address of the indexer
     * @param delegator The address of the delegator
     * @param tokens The amount of tokens withdrawn
     */
    event StakeDelegatedWithdrawn(address indexed indexer, address indexed delegator, uint256 tokens);

    /**
     * @notice Emitted when tokens are added to a delegation pool's reserve.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param tokens The amount of tokens withdrawn
     */
    event TokensToDelegationPoolAdded(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    /**
     * @notice Emitted when a service provider sets delegation fee cuts for a verifier.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param paymentType The payment type for which the fee cut is set, as defined in {IGraphPayments}
     * @param feeCut The fee cut set, in PPM
     */
    event DelegationFeeCutSet(
        address indexed serviceProvider,
        address indexed verifier,
        IGraphPayments.PaymentTypes indexed paymentType,
        uint256 feeCut
    );

    // -- Events: thawing --

    /**
     * @notice Emitted when a thaw request is created.
     * @dev Can be emitted by the service provider when thawing stake or by the delegator when undelegating.
     * @param requestType The type of thaw request
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param owner The address of the owner of the thaw request.
     * @param shares The amount of shares being thawed
     * @param thawingUntil The timestamp until the stake is thawed
     * @param thawRequestId The ID of the thaw request
     */
    event ThawRequestCreated(
        IHorizonStakingTypes.ThawRequestType indexed requestType,
        address indexed serviceProvider,
        address indexed verifier,
        address owner,
        uint256 shares,
        uint64 thawingUntil,
        bytes32 thawRequestId
    );

    /**
     * @notice Emitted when a thaw request is fulfilled, meaning the stake is released.
     * @param requestType The type of thaw request
     * @param thawRequestId The ID of the thaw request
     * @param tokens The amount of tokens being released
     * @param shares The amount of shares being released
     * @param thawingUntil The timestamp until the stake has thawed
     * @param valid Whether the thaw request was valid at the time of fulfillment
     */
    event ThawRequestFulfilled(
        IHorizonStakingTypes.ThawRequestType indexed requestType,
        bytes32 indexed thawRequestId,
        uint256 tokens,
        uint256 shares,
        uint64 thawingUntil,
        bool valid
    );

    /**
     * @notice Emitted when a series of thaw requests are fulfilled.
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param owner The address of the owner of the thaw requests
     * @param thawRequestsFulfilled The number of thaw requests fulfilled
     * @param tokens The total amount of tokens being released
     * @param requestType The type of thaw request
     */
    event ThawRequestsFulfilled(
        IHorizonStakingTypes.ThawRequestType indexed requestType,
        address indexed serviceProvider,
        address indexed verifier,
        address owner,
        uint256 thawRequestsFulfilled,
        uint256 tokens
    );

    // -- Events: governance --

    /**
     * @notice Emitted when the global maximum thawing period allowed for provisions is set.
     * @param maxThawingPeriod The new maximum thawing period
     */
    event MaxThawingPeriodSet(uint64 maxThawingPeriod);

    /**
     * @notice Emitted when a verifier is allowed or disallowed to be used for locked provisions.
     * @param verifier The address of the verifier
     * @param allowed Whether the verifier is allowed or disallowed
     */
    event AllowedLockedVerifierSet(address indexed verifier, bool allowed);

    /**
     * @notice Emitted when the legacy global thawing period is set to zero.
     * @dev This marks the end of the transition period.
     */
    event ThawingPeriodCleared();

    /**
     * @notice Emitted when the delegation slashing global flag is set.
     */
    event DelegationSlashingEnabled();

    // -- Errors: tokens

    /**
     * @notice Thrown when operating a zero token amount is not allowed.
     */
    error HorizonStakingInvalidZeroTokens();

    /**
     * @notice Thrown when a minimum token amount is required to operate but it's not met.
     * @param tokens The actual token amount
     * @param minRequired The minimum required token amount
     */
    error HorizonStakingInsufficientTokens(uint256 tokens, uint256 minRequired);

    /**
     * @notice Thrown when the amount of tokens exceeds the maximum allowed to operate.
     * @param tokens The actual token amount
     * @param maxTokens The maximum allowed token amount
     */
    error HorizonStakingTooManyTokens(uint256 tokens, uint256 maxTokens);

    // -- Errors: provision --

    /**
     * @notice Thrown when attempting to operate with a provision that does not exist.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     */
    error HorizonStakingInvalidProvision(address serviceProvider, address verifier);

    /**
     * @notice Thrown when the caller is not authorized to operate on a provision.
     * @param caller The caller address
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     */
    error HorizonStakingNotAuthorized(address serviceProvider, address verifier, address caller);

    /**
     * @notice Thrown when attempting to create a provision with a verifier other than the
     * subgraph data service. This restriction only applies during the transition period.
     * @param verifier The verifier address
     */
    error HorizonStakingInvalidVerifier(address verifier);

    /**
     * @notice Thrown when attempting to create a provision with an invalid maximum verifier cut.
     * @param maxVerifierCut The maximum verifier cut
     */
    error HorizonStakingInvalidMaxVerifierCut(uint32 maxVerifierCut);

    /**
     * @notice Thrown when attempting to create a provision with an invalid thawing period.
     * @param thawingPeriod The thawing period
     * @param maxThawingPeriod The maximum `thawingPeriod` allowed
     */
    error HorizonStakingInvalidThawingPeriod(uint64 thawingPeriod, uint64 maxThawingPeriod);

    /**
     * @notice Thrown when attempting to create a provision for a data service that already has a provision.
     */
    error HorizonStakingProvisionAlreadyExists();

    // -- Errors: stake --

    /**
     * @notice Thrown when the service provider has insufficient idle stake to operate.
     * @param tokens The actual token amount
     * @param minTokens The minimum required token amount
     */
    error HorizonStakingInsufficientIdleStake(uint256 tokens, uint256 minTokens);

    /**
     * @notice Thrown during the transition period when the service provider has insufficient stake to
     * cover their existing legacy allocations.
     * @param tokens The actual token amount
     * @param minTokens The minimum required token amount
     */
    error HorizonStakingInsufficientStakeForLegacyAllocations(uint256 tokens, uint256 minTokens);

    // -- Errors: delegation --

    /**
     * @notice Thrown when delegation shares obtained are below the expected amount.
     * @param shares The actual share amount
     * @param minShares The minimum required share amount
     */
    error HorizonStakingSlippageProtection(uint256 shares, uint256 minShares);

    /**
     * @notice Thrown when operating a zero share amount is not allowed.
     */
    error HorizonStakingInvalidZeroShares();

    /**
     * @notice Thrown when a minimum share amount is required to operate but it's not met.
     * @param shares The actual share amount
     * @param minShares The minimum required share amount
     */
    error HorizonStakingInsufficientShares(uint256 shares, uint256 minShares);

    /**
     * @notice Thrown when as a result of slashing delegation pool has no tokens but has shares.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     */
    error HorizonStakingInvalidDelegationPoolState(address serviceProvider, address verifier);

    /**
     * @notice Thrown when attempting to operate with a delegation pool that does not exist.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     */
    error HorizonStakingInvalidDelegationPool(address serviceProvider, address verifier);

    /**
     * @notice Thrown when the minimum token amount required for delegation is not met.
     * @param tokens The actual token amount
     * @param minTokens The minimum required token amount
     */
    error HorizonStakingInsufficientDelegationTokens(uint256 tokens, uint256 minTokens);

    /**
     * @notice Thrown when attempting to redelegate with a serivce provider that is the zero address.
     */
    error HorizonStakingInvalidServiceProviderZeroAddress();

    /**
     * @notice Thrown when attempting to redelegate with a verifier that is the zero address.
     */
    error HorizonStakingInvalidVerifierZeroAddress();

    // -- Errors: thaw requests --

    /**
     * @notice Thrown when attempting to fulfill a thaw request but there is nothing thawing.
     */
    error HorizonStakingNothingThawing();

    /**
     * @notice Thrown when a service provider has too many thaw requests.
     */
    error HorizonStakingTooManyThawRequests();

    /**
     * @notice Thrown when attempting to withdraw tokens that have not thawed (legacy undelegate).
     */
    error HorizonStakingNothingToWithdraw();

    // -- Errors: misc --
    /**
     * @notice Thrown during the transition period when attempting to withdraw tokens that are still thawing.
     * @dev Note this thawing refers to the global thawing period applied to legacy allocated tokens,
     * it does not refer to thaw requests.
     * @param until The block number until the stake is locked
     */
    error HorizonStakingStillThawing(uint256 until);

    /**
     * @notice Thrown when a service provider attempts to operate on verifiers that are not allowed.
     * @dev Only applies to stake from locked wallets.
     * @param verifier The verifier address
     */
    error HorizonStakingVerifierNotAllowed(address verifier);

    /**
     * @notice Thrown when a service provider attempts to change their own operator access.
     */
    error HorizonStakingCallerIsServiceProvider();

    /**
     * @notice Thrown when trying to set a delegation fee cut that is not valid.
     * @param feeCut The fee cut
     */
    error HorizonStakingInvalidDelegationFeeCut(uint256 feeCut);

    /**
     * @notice Thrown when a legacy slash fails.
     */
    error HorizonStakingLegacySlashFailed();

    /**
     * @notice Thrown when there attempting to slash a provision with no tokens to slash.
     */
    error HorizonStakingNoTokensToSlash();

    // -- Functions --

    /**
     * @notice Deposit tokens on the staking contract.
     * @dev Pulls tokens from the caller.
     *
     * Requirements:
     * - `_tokens` cannot be zero.
     * - Caller must have previously approved this contract to pull tokens from their balance.
     *
     * Emits a {HorizonStakeDeposited} event.
     *
     * @param tokens Amount of tokens to stake
     */
    function stake(uint256 tokens) external;

    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider.
     * @dev Pulls tokens from the caller.
     *
     * Requirements:
     * - `_tokens` cannot be zero.
     * - Caller must have previously approved this contract to pull tokens from their balance.
     *
     * Emits a {HorizonStakeDeposited} event.
     *
     * @param serviceProvider Address of the service provider
     * @param tokens Amount of tokens to stake
     */
    function stakeTo(address serviceProvider, uint256 tokens) external;

    // can be called by anyone if the service provider has provisioned stake to this verifier
    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider,
     * provisioned to a specific verifier.
     * @dev Requirements:
     * - The `serviceProvider` must have previously provisioned stake to `verifier`.
     * - `_tokens` cannot be zero.
     * - Caller must have previously approved this contract to pull tokens from their balance.
     *
     * Emits {HorizonStakeDeposited} and {ProvisionIncreased} events.
     *
     * @param serviceProvider Address of the service provider
     * @param verifier Address of the verifier
     * @param tokens Amount of tokens to stake
     */
    function stakeToProvision(address serviceProvider, address verifier, uint256 tokens) external;

    /**
     * @notice Move idle stake back to the owner's account.
     * Stake is removed from the protocol:
     * - During the transition period it's locked for a period of time before it can be withdrawn
     *   by calling {withdraw}.
     * - After the transition period it's immediately withdrawn.
     * Note that after the transition period if there are tokens still locked they will have to be
     * withdrawn by calling {withdraw}.
     * @dev Requirements:
     * - `_tokens` cannot be zero.
     * - `_serviceProvider` must have enough idle stake to cover the staking amount and any
     *   legacy allocation.
     *
     * Emits a {HorizonStakeLocked} event during the transition period.
     * Emits a {HorizonStakeWithdrawn} event after the transition period.
     *
     * @param tokens Amount of tokens to unstake
     */
    function unstake(uint256 tokens) external;

    /**
     * @notice Withdraw service provider tokens once the thawing period (initiated by {unstake}) has passed.
     * All thawed tokens are withdrawn.
     * @dev This is only needed during the transition period while we still have
     * a global lock. After that, unstake() will automatically withdraw.
     */
    function withdraw() external;

    /**
     * @notice Provision stake to a verifier. The tokens will be locked with a thawing period
     * and will be slashable by the verifier. This is the main mechanism to provision stake to a data
     * service, where the data service is the verifier.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @dev During the transition period, only the subgraph data service can be used as a verifier. This
     * prevents an escape hatch for legacy allocation stake.
     * @dev Requirements:
     * - `tokens` cannot be zero.
     * - The `serviceProvider` must have enough idle stake to cover the tokens to provision.
     * - `maxVerifierCut` must be a valid PPM.
     * - `thawingPeriod` must be less than or equal to `_maxThawingPeriod`.
     *
     * Emits a {ProvisionCreated} event.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned (who will be able to slash the tokens)
     * @param tokens The amount of tokens that will be locked and slashable
     * @param maxVerifierCut The maximum cut, expressed in PPM, that a verifier can transfer instead of burning when slashing
     * @param thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    function provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external;

    /**
     * @notice Adds tokens from the service provider's idle stake to a provision
     * @dev
     *
     * Requirements:
     * - The `serviceProvider` must have previously provisioned stake to `verifier`.
     * - `tokens` cannot be zero.
     * - The `serviceProvider` must have enough idle stake to cover the tokens to add.
     *
     * Emits a {ProvisionIncreased} event.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param tokens The amount of tokens to add to the provision
     */
    function addToProvision(address serviceProvider, address verifier, uint256 tokens) external;

    /**
     * @notice Start thawing tokens to remove them from a provision.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     *
     * Note that removing tokens from a provision is a two step process:
     * - First the tokens are thawed using this function.
     * - Then after the thawing period, the tokens are removed from the provision using {deprovision}
     *   or {reprovision}.
     *
     * @dev Requirements:
     * - The provision must have enough tokens available to thaw.
     * - `tokens` cannot be zero.
     *
     * Emits {ProvisionThawed} and {ThawRequestCreated} events.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     * @param tokens The amount of tokens to thaw
     * @return The ID of the thaw request
     */
    function thaw(address serviceProvider, address verifier, uint256 tokens) external returns (bytes32);

    /**
     * @notice Remove tokens from a provision and move them back to the service provider's idle stake.
     * @dev The parameter `nThawRequests` can be set to a non zero value to fulfill a specific number of thaw
     * requests in the event that fulfilling all of them results in a gas limit error.
     *
     * Requirements:
     * - Must have previously initiated a thaw request using {thaw}.
     *
     * Emits {ThawRequestFulfilled}, {ThawRequestsFulfilled} and {TokensDeprovisioned} events.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param nThawRequests The number of thaw requests to fulfill. Set to 0 to fulfill all thaw requests.
     */
    function deprovision(address serviceProvider, address verifier, uint256 nThawRequests) external;

    /**
     * @notice Move already thawed stake from one provision into another provision
     * This function can be called by the service provider or by an operator authorized by the provider
     * for the two corresponding verifiers.
     * @dev Requirements:
     * - Must have previously initiated a thaw request using {thaw}.
     * - `tokens` cannot be zero.
     * - The `serviceProvider` must have previously provisioned stake to `newVerifier`.
     * - The `serviceProvider` must have enough idle stake to cover the tokens to add.
     *
     * Emits {ThawRequestFulfilled}, {ThawRequestsFulfilled}, {TokensDeprovisioned} and {ProvisionIncreased}
     * events.
     *
     * @param serviceProvider The service provider address
     * @param oldVerifier The verifier address for which the tokens are currently provisioned
     * @param newVerifier The verifier address for which the tokens will be provisioned
     * @param nThawRequests The number of thaw requests to fulfill. Set to 0 to fulfill all thaw requests.
     */
    function reprovision(
        address serviceProvider,
        address oldVerifier,
        address newVerifier,
        uint256 nThawRequests
    ) external;

    /**
     * @notice Stages a provision parameter update. Note that the change is not effective until the verifier calls
     * {acceptProvisionParameters}.
     * @dev This two step update process prevents the service provider from changing the parameters
     * without the verifier's consent.
     *
     * Emits a {ProvisionParametersStaged} event if at least one of the parameters changed.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param maxVerifierCut The proposed maximum cut, expressed in PPM of the slashed amount, that a verifier can take for
     * themselves when slashing
     * @param thawingPeriod The proposed period in seconds that the tokens will be thawing before they can be removed from
     * the provision
     */
    function setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external;

    /**
     * @notice Accepts a staged provision parameter update.
     * @dev Only the provision's verifier can call this function.
     *
     * Emits a {ProvisionParametersSet} event.
     *
     * @param serviceProvider The service provider address
     */
    function acceptProvisionParameters(address serviceProvider) external;

    /**
     * @notice Delegate tokens to a provision.
     * @dev Requirements:
     * - `tokens` cannot be zero.
     * - Caller must have previously approved this contract to pull tokens from their balance.
     * - The provision must exist.
     *
     * Emits a {TokensDelegated} event.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param tokens The amount of tokens to delegate
     * @param minSharesOut The minimum amount of shares to accept, slippage protection.
     */
    function delegate(address serviceProvider, address verifier, uint256 tokens, uint256 minSharesOut) external;

    /**
     * @notice Add tokens to a delegation pool without issuing shares.
     * Used by data services to pay delegation fees/rewards.
     * Delegators SHOULD NOT call this function.
     *
     * @dev Requirements:
     * - `tokens` cannot be zero.
     * - Caller must have previously approved this contract to pull tokens from their balance.
     *
     * Emits a {TokensToDelegationPoolAdded} event.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     * @param tokens The amount of tokens to add to the delegation pool
     */
    function addToDelegationPool(address serviceProvider, address verifier, uint256 tokens) external;

    /**
     * @notice Undelegate tokens from a provision and start thawing them.
     * Note that undelegating tokens from a provision is a two step process:
     * - First the tokens are thawed using this function.
     * - Then after the thawing period, the tokens are removed from the provision using {withdrawDelegated}.
     *
     * Requirements:
     * - `shares` cannot be zero.
     *
     * Emits a {TokensUndelegated} and {ThawRequestCreated} event.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param shares The amount of shares to undelegate
     * @return The ID of the thaw request
     */
    function undelegate(address serviceProvider, address verifier, uint256 shares) external returns (bytes32);

    /**
     * @notice Withdraw undelegated tokens from a provision after thawing.
     * @dev The parameter `nThawRequests` can be set to a non zero value to fulfill a specific number of thaw
     * requests in the event that fulfilling all of them results in a gas limit error.
     * @dev If the delegation pool was completely slashed before withdrawing, calling this function will fulfill
     * the thaw requests with an amount equal to zero.
     *
     * Requirements:
     * - Must have previously initiated a thaw request using {undelegate}.
     *
     * Emits {ThawRequestFulfilled}, {ThawRequestsFulfilled} and {DelegatedTokensWithdrawn} events.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param nThawRequests The number of thaw requests to fulfill. Set to 0 to fulfill all thaw requests.
     */
    function withdrawDelegated(address serviceProvider, address verifier, uint256 nThawRequests) external;

    /**
     * @notice Re-delegate undelegated tokens from a provision after thawing to a `newServiceProvider` and `newVerifier`.
     * @dev The parameter `nThawRequests` can be set to a non zero value to fulfill a specific number of thaw
     * requests in the event that fulfilling all of them results in a gas limit error.
     *
     * Requirements:
     * - Must have previously initiated a thaw request using {undelegate}.
     * - `newServiceProvider` and `newVerifier` must not be the zero address.
     * - `newServiceProvider` must have previously provisioned stake to `newVerifier`.
     *
     * Emits {ThawRequestFulfilled}, {ThawRequestsFulfilled} and {DelegatedTokensWithdrawn} events.
     *
     * @param oldServiceProvider The old service provider address
     * @param oldVerifier The old verifier address
     * @param newServiceProvider The address of a new service provider
     * @param newVerifier The address of a new verifier
     * @param minSharesForNewProvider The minimum amount of shares to accept for the new service provider
     * @param nThawRequests The number of thaw requests to fulfill. Set to 0 to fulfill all thaw requests.
     */
    function redelegate(
        address oldServiceProvider,
        address oldVerifier,
        address newServiceProvider,
        address newVerifier,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) external;

    /**
     * @notice Set the fee cut for a verifier on a specific payment type.
     * @dev Emits a {DelegationFeeCutSet} event.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address
     * @param paymentType The payment type for which the fee cut is set, as defined in {IGraphPayments}
     * @param feeCut The fee cut to set, in PPM
     */
    function setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType,
        uint256 feeCut
    ) external;

    /**
     * @notice Delegate tokens to the subgraph data service provision.
     * This function is for backwards compatibility with the legacy staking contract.
     * It only allows delegating to the subgraph data service and DOES NOT have slippage protection.
     * @dev See {delegate}.
     * @param serviceProvider The service provider address
     * @param tokens The amount of tokens to delegate
     */
    function delegate(address serviceProvider, uint256 tokens) external;

    /**
     * @notice Undelegate tokens from the subgraph data service provision and start thawing them.
     * This function is for backwards compatibility with the legacy staking contract.
     * It only allows undelegating from the subgraph data service.
     * @dev See {undelegate}.
     * @param serviceProvider The service provider address
     * @param shares The amount of shares to undelegate
     */
    function undelegate(address serviceProvider, uint256 shares) external;

    /**
     * @notice Withdraw undelegated tokens from the subgraph data service provision after thawing.
     * This function is for backwards compatibility with the legacy staking contract.
     * It only allows withdrawing tokens undelegated before horizon upgrade.
     * @dev See {delegate}.
     * @param serviceProvider The service provider address
     * @param deprecated Deprecated parameter kept for backwards compatibility
     * @return The amount of tokens withdrawn
     */
    function withdrawDelegated(
        address serviceProvider,
        address deprecated // kept for backwards compatibility
    ) external returns (uint256);

    /**
     * @notice Slash a service provider. This can only be called by a verifier to which
     * the provider has provisioned stake, and up to the amount of tokens they have provisioned.
     * If the service provider's stake is not enough, the associated delegation pool might be slashed
     * depending on the value of the global delegation slashing flag.
     *
     * Part of the slashed tokens are sent to the `verifierDestination` as a reward.
     *
     * @dev Requirements:
     * - `tokens` must be less than or equal to the amount of tokens provisioned by the service provider.
     * - `tokensVerifier` must be less than the provision's tokens times the provision's maximum verifier cut.
     *
     * Emits a {ProvisionSlashed} and {VerifierTokensSent} events.
     * Emits a {DelegationSlashed} or {DelegationSlashingSkipped} event depending on the global delegation slashing
     * flag.
     *
     * @param serviceProvider The service provider to slash
     * @param tokens The amount of tokens to slash
     * @param tokensVerifier The amount of tokens to transfer instead of burning
     * @param verifierDestination The address to transfer the verifier cut to
     */
    function slash(
        address serviceProvider,
        uint256 tokens,
        uint256 tokensVerifier,
        address verifierDestination
    ) external;

    /**
     * @notice Provision stake to a verifier using locked tokens (i.e. from GraphTokenLockWallets).
     * @dev See {provision}.
     *
     * Additional requirements:
     * - The `verifier` must be allowed to be used for locked provisions.
     *
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned (who will be able to slash the tokens)
     * @param tokens The amount of tokens that will be locked and slashable
     * @param maxVerifierCut The maximum cut, expressed in PPM, that a verifier can transfer instead of burning when slashing
     * @param thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    function provisionLocked(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external;

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a verifier.
     *
     * @dev See {setOperator}.
     * Additional requirements:
     * - The `verifier` must be allowed to be used for locked provisions.
     *
     * @param verifier The verifier / data service on which they'll be allowed to operate
     * @param operator Address to authorize or unauthorize
     * @param allowed Whether the operator is authorized or not
     */
    function setOperatorLocked(address verifier, address operator, bool allowed) external;

    /**
     * @notice Sets a verifier as a globally allowed verifier for locked provisions.
     * @dev This function can only be called by the contract governor, it's used to maintain
     * a whitelist of verifiers that do not allow the stake from a locked wallet to escape the lock.
     * @dev Emits a {AllowedLockedVerifierSet} event.
     * @param verifier The verifier address
     * @param allowed Whether the verifier is allowed or not
     */
    function setAllowedLockedVerifier(address verifier, bool allowed) external;

    /**
     * @notice Set the global delegation slashing flag to true.
     * @dev This function can only be called by the contract governor.
     */
    function setDelegationSlashingEnabled() external;

    /**
     * @notice Clear the legacy global thawing period.
     * This signifies the end of the transition period, after which no legacy allocations should be left.
     * @dev This function can only be called by the contract governor.
     * @dev Emits a {ThawingPeriodCleared} event.
     */
    function clearThawingPeriod() external;

    /**
     * @notice Sets the global maximum thawing period allowed for provisions.
     * @param maxThawingPeriod The new maximum thawing period, in seconds
     */
    function setMaxThawingPeriod(uint64 maxThawingPeriod) external;

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @dev Emits a {OperatorSet} event.
     * @param verifier The verifier / data service on which they'll be allowed to operate
     * @param operator Address to authorize or unauthorize
     * @param allowed Whether the operator is authorized or not
     */
    function setOperator(address verifier, address operator, bool allowed) external;

    /**
     * @notice Check if an operator is authorized for the caller on a specific verifier / data service.
     * @param serviceProvider The service provider on behalf of whom they're claiming to act
     * @param verifier The verifier / data service on which they're claiming to act
     * @param operator The address to check for auth
     * @return Whether the operator is authorized or not
     */
    function isAuthorized(address serviceProvider, address verifier, address operator) external view returns (bool);

    /**
     * @notice Get the address of the staking extension.
     * @return The address of the staking extension
     */
    function getStakingExtension() external view returns (address);
}
