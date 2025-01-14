// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";
import { IGraphPayments } from "../IGraphPayments.sol";

import { LinkedList } from "../../libraries/LinkedList.sol";

/**
 * @title Interface for the {HorizonStakingBase} contract.
 * @notice Provides getters for {HorizonStaking} and {HorizonStakingExtension} storage variables.
 * @dev Most functions operate over {HorizonStaking} provisions. To uniquely identify a provision
 * functions take `serviceProvider` and `verifier` addresses.
 */
interface IHorizonStakingBase {
    /**
     * @notice Emitted when a service provider stakes tokens.
     * @dev TODO: After transition period move to IHorizonStakingMain. Temporarily it
     * needs to be here since it's emitted by {_stake} which is used by both {HorizonStaking}
     * and {HorizonStakingExtension}.
     * @param serviceProvider The address of the service provider.
     * @param tokens The amount of tokens staked.
     */
    event StakeDeposited(address indexed serviceProvider, uint256 tokens);

    /**
     * @notice Thrown when using an invalid thaw request type.
     */
    error HorizonStakingInvalidThawRequestType();

    /**
     * @notice Gets the details of a service provider.
     * @param serviceProvider The address of the service provider.
     */
    function getServiceProvider(
        address serviceProvider
    ) external view returns (IHorizonStakingTypes.ServiceProvider memory);

    /**
     * @notice Gets the stake of a service provider.
     * @param serviceProvider The address of the service provider.
     * @return The amount of tokens staked.
     */
    function getStake(address serviceProvider) external view returns (uint256);

    /**
     * @notice Gets the service provider's idle stake which is the stake that is not being
     * used for any provision. Note that this only includes service provider's self stake.
     * @param serviceProvider The address of the service provider.
     * @return The amount of tokens that are idle.
     */
    function getIdleStake(address serviceProvider) external view returns (uint256);

    /**
     * @notice Gets the details of delegation pool.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @return The delegation pool details.
     */
    function getDelegationPool(
        address serviceProvider,
        address verifier
    ) external view returns (IHorizonStakingTypes.DelegationPool memory);

    /**
     * @notice Gets the details of a delegation.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @param delegator The address of the delegator.
     * @return The delegation details.
     */
    function getDelegation(
        address serviceProvider,
        address verifier,
        address delegator
    ) external view returns (IHorizonStakingTypes.Delegation memory);

    /**
     * @notice Gets the delegation fee cut for a payment type.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @param paymentType The payment type as defined by {IGraphPayments.PaymentTypes}.
     * @return The delegation fee cut in PPM.
     */
    function getDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType
    ) external view returns (uint256);

    /**
     * @notice Gets the details of a provision.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @return The provision details.
     */
    function getProvision(
        address serviceProvider,
        address verifier
    ) external view returns (IHorizonStakingTypes.Provision memory);

    /**
     * @notice Gets the tokens available in a provision.
     * Tokens available are the tokens in a provision that are not thawing. Includes service
     * provider's and delegator's stake.
     *
     * Allows specifying a `delegationRatio` which caps the amount of delegated tokens that are
     * considered available.
     *
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @param delegationRatio The delegation ratio.
     * @return The amount of tokens available.
     */
    function getTokensAvailable(
        address serviceProvider,
        address verifier,
        uint32 delegationRatio
    ) external view returns (uint256);

    /**
     * @notice Gets the service provider's tokens available in a provision.
     * @dev Calculated as the tokens available minus the tokens thawing.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @return The amount of tokens available.
     */
    function getProviderTokensAvailable(address serviceProvider, address verifier) external view returns (uint256);

    /**
     * @notice Gets the delegator's tokens available in a provision.
     * @dev Calculated as the tokens available minus the tokens thawing.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     * @return The amount of tokens available.
     */
    function getDelegatedTokensAvailable(address serviceProvider, address verifier) external view returns (uint256);

    // /**
    //  * @notice Gets a thaw request.
    //  * @param thawRequestType The type of thaw request.
    //  * @param thawRequestId The id of the thaw request.
    //  * @return The thaw request details.
    //  */
    // function getThawRequest(
    //     IHorizonStakingTypes.ThawRequestType thawRequestType,
    //     bytes32 thawRequestId
    // ) external view returns (IHorizonStakingTypes.ThawRequest memory);

    // /**
    //  * @notice Gets the metadata of a thaw request list.
    //  * Service provider and delegators each have their own thaw request list per provision.
    //  * Metadata includes the head and tail of the list, plus the total number of thaw requests.
    //  * @param thawRequestType The type of thaw request.
    //  * @param serviceProvider The address of the service provider.
    //  * @param verifier The address of the verifier.
    //  * @param owner The owner of the thaw requests. Use either the service provider or delegator address.
    //  * @return The thaw requests list metadata.
    //  */
    // function getThawRequestList(
    //     IHorizonStakingTypes.ThawRequestType thawRequestType,
    //     address serviceProvider,
    //     address verifier,
    //     address owner
    // ) external view returns (LinkedList.List memory);

    // /**
    //  * @notice Gets the amount of thawed tokens for a given provision.
    //  * @param thawRequestType The type of thaw request.
    //  * @param serviceProvider The address of the service provider.
    //  * @param verifier The address of the verifier.
    //  * @param owner The owner of the thaw requests. Use either the service provider or delegator address.
    //  * @return The amount of thawed tokens.
    //  */
    // function getThawedTokens(
    //     IHorizonStakingTypes.ThawRequestType thawRequestType,
    //     address serviceProvider,
    //     address verifier,
    //     address owner
    // ) external view returns (uint256);

    /**
     * @notice Gets the maximum allowed thawing period for a provision.
     */
    function getMaxThawingPeriod() external view returns (uint64);

    /**
     * @notice Return true if the verifier is an allowed locked verifier.
     * @param verifier Address of the verifier
     * @return True if verifier is allowed locked verifier, false otherwise
     */
    function isAllowedLockedVerifier(address verifier) external view returns (bool);

    /**
     * @notice Return true if delegation slashing is enabled, false otherwise.
     */
    function isDelegationSlashingEnabled() external view returns (bool);
}
