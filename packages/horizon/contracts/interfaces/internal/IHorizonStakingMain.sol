// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { IHorizonStakingBase } from "./IHorizonStakingBase.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

interface IHorizonStakingMain is IHorizonStakingBase {
    /**
     * @dev Emitted when `serviceProvider` withdraws `tokens` amount.
     */
    event StakeWithdrawn(address indexed serviceProvider, uint256 tokens);

    /**
     * @dev Emitted when `serviceProvider` locks `tokens` amount until `until`.
     */
    event StakeLocked(address indexed serviceProvider, uint256 tokens, uint256 until);

    /**
     * @dev Emitted when a service provider provisions staked tokens to a verifier
     */
    event ProvisionCreated(
        address indexed serviceProvider,
        address indexed verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    );

    /**
     * @dev Emitted when a service provider increases the tokens in a provision
     */
    event ProvisionIncreased(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event ProvisionThawed(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event TokensDeprovisioned(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event ProvisionSlashed(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event DelegationSlashed(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event DelegationSlashingSkipped(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event VerifierTokensSent(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed destination,
        uint256 tokens
    );

    event TokensDelegated(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed delegator,
        uint256 tokens
    );

    event TokensUndelegated(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed delegator,
        uint256 tokens
    );

    event DelegatedTokensWithdrawn(
        address indexed serviceProvider,
        address indexed verifier,
        address indexed delegator,
        uint256 tokens
    );

    event DelegationSlashingEnabled(bool enabled);

    event AllowedLockedVerifierSet(address indexed verifier, bool allowed);

    event TokensToDelegationPoolAdded(address indexed serviceProvider, address indexed verifier, uint256 tokens);

    event ProvisionParametersStaged(
        address indexed serviceProvider,
        address indexed verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    );

    event ProvisionParametersSet(
        address indexed serviceProvider,
        address indexed verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    );

    event ThawingPeriodCleared();
    event MaxThawingPeriodSet(uint64 maxThawingPeriod);

    /**
     * @dev Emitted when an operator is allowed or denied by a service provider for a particular data service
     */
    event OperatorSet(
        address indexed serviceProvider,
        address indexed operator,
        address indexed verifier,
        bool allowed
    );

    event DelegationFeeCutSet(
        address indexed serviceProvider,
        address indexed verifier,
        IGraphPayments.PaymentTypes indexed paymentType,
        uint256 feeCut
    );

    error HorizonStakingInvalidZeroTokens();
    error HorizonStakingInvalidProvision(address serviceProvider, address verifier);
    error HorizonStakingInvalidTokens(uint256 tokens, uint256 minTokens);
    error HorizonStakingInvalidMaxVerifierCut(uint32 maxVerifierCut, uint32 maxAllowedCut);
    error HorizonStakingInvalidThawingPeriod(uint64 thawingPeriod, uint64 maxThawingPeriod);
    error HorizonStakingNotAuthorized(address caller, address serviceProvider, address verifier);
    error HorizonStakingInsufficientCapacity();
    error HorizonStakingInsufficientCapacityForLegacyAllocations();
    error HorizonStakingInsufficientTokensAvailable(uint256 tokensAvailable, uint256 tokensRequired);
    error HorizonStakingInsufficientTokens(uint256 available, uint256 tokensRequired);
    error HorizonStakingSlippageProtection(uint256 minExpectedShares, uint256 actualShares);
    error HorizonStakingVerifierNotAllowed(address verifier);
    error HorizonStakingVerifierTokensTooHigh(uint256 tokensVerifier, uint256 maxVerifierTokens);
    error HorizonStakingNotEnoughDelegation(uint256 tokensAvailable, uint256 tokensRequired);
    error HorizonStakingInvalidZeroShares();
    error HorizonStakingInvalidSharesAmount(uint256 sharesAvailable, uint256 sharesRequired);
    error HorizonStakingCallerIsServiceProvider();
    error HorizonStakingStillThawing(uint256 until);
    error HorizonStakingCannotFulfillThawRequest();

    // deposit stake
    function stake(uint256 tokens) external;

    function stakeTo(address serviceProvider, uint256 tokens) external;

    // can be called by anyone if the service provider has provisioned stake to this verifier
    function stakeToProvision(address serviceProvider, address verifier, uint256 tokens) external;

    // create a provision
    function provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external;

    /**
     * @notice Provision stake to a verifier using locked tokens (i.e. from GraphTokenLockWallets). The tokens will be locked with a thawing period
     * and will be slashable by the verifier. This is the main mechanism to provision stake to a data
     * service, where the data service is the verifier. Only authorized verifiers can be used.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
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

    // initiate a thawing to remove tokens from a provision
    function thaw(address serviceProvider, address verifier, uint256 tokens) external returns (bytes32);

    // add more tokens from idle stake to an existing provision
    function addToProvision(address serviceProvider, address verifier, uint256 tokens) external;

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(address serviceProvider, address verifier, uint256 nThawRequests) external;

    // moves thawed stake from one provision into another provision
    function reprovision(
        address serviceProvider,
        address oldVerifier,
        address newVerifier,
        uint256 tokens,
        uint256 nThawRequests
    ) external;

    // moves thawed stake back to the owner's account - stake is removed from the protocol
    function unstake(uint256 tokens) external;

    // delegate tokens to a provider on a data service
    function delegate(address serviceProvider, address verifier, uint256 tokens, uint256 minSharesOut) external;

    // undelegate (thaw) delegated tokens from a provision
    function undelegate(address serviceProvider, address verifier, uint256 shares) external returns (bytes32);

    // withdraw delegated tokens after thawing
    function withdrawDelegated(
        address serviceProvider,
        address verifier,
        address newServiceProvider,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) external;

    function slash(
        address serviceProvider,
        uint256 tokens,
        uint256 tokensVerifier,
        address verifierDestination
    ) external;

    /**
     * @notice Withdraw service provider tokens once the thawing period has passed.
     * @dev This is only needed during the transition period while we still have
     * a global lock. After that, unstake() will also withdraw.
     */
    function withdraw() external;

    function setDelegationSlashingEnabled(bool enabled) external;

    function setMaxThawingPeriod(uint64 maxThawingPeriod) external;

    function setAllowedLockedVerifier(address verifier, bool allowed) external;

    /**
     * @notice Add tokens to a delegation pool (without getting shares).
     * Used by data services to pay delegation fees/rewards.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     * @param tokens The amount of tokens to add to the delegation pool
     */
    function addToDelegationPool(address serviceProvider, address verifier, uint256 tokens) external;

    function setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external;

    function acceptProvisionParameters(address serviceProvider) external;

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param operator Address to authorize or unauthorize
     * @param verifier The verifier / data service on which they'll be allowed to operate
     * @param allowed Whether the operator is authorized or not
     */
    function setOperator(address operator, address verifier, bool allowed) external;

    // for vesting contracts
    function setOperatorLocked(address operator, address verifier, bool allowed) external;

    function setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType,
        uint256 feeCut
    ) external;

    /**
     * @notice Check if an operator is authorized for the caller on a specific verifier / data service.
     * @param operator The address to check for auth
     * @param serviceProvider The service provider on behalf of whom they're claiming to act
     * @param verifier The verifier / data service on which they're claiming to act
     */
    function isAuthorized(address operator, address serviceProvider, address verifier) external view returns (bool);

    function clearThawingPeriod() external;
    function delegate(address serviceProvider, uint256 tokens) external;
    function undelegate(address serviceProvider, uint256 shares) external;
    function withdrawDelegated(address serviceProvider, address newServiceProvider) external;
}
