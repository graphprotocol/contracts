// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";
import { IGraphPayments } from "./IGraphPayments.sol";

interface IHorizonStakingBase {
    /**
     * @dev Emitted when `serviceProvider` stakes `tokens` amount.
     * @dev TODO(after transition period): move to IHorizonStakingMain
     */
    event StakeDeposited(address indexed serviceProvider, uint256 tokens);

    /**
     * @dev Emitted when `delegator` delegated `tokens` to the `serviceProvider`, the delegator
     * gets `shares` for the delegation pool proportionally to the tokens staked.
     * This event is here for backwards compatibility, the tokens are delegated
     * on the subgraph data service provision.
     * @dev TODO(after transition period): move to IHorizonStakingMain
     */
    event StakeDelegated(address indexed serviceProvider, address indexed delegator, uint256 tokens, uint256 shares);

    function getStake(address serviceProvider) external view returns (uint256);

    function getDelegatedTokensAvailable(address serviceProvider, address verifier) external view returns (uint256);

    function getTokensAvailable(
        address serviceProvider,
        address verifier,
        uint32 delegationRatio
    ) external view returns (uint256);

    function getServiceProvider(
        address serviceProvider
    ) external view returns (IHorizonStakingTypes.ServiceProvider memory);

    function getMaxThawingPeriod() external view returns (uint64);

    function getDelegationPool(
        address serviceProvider,
        address verifier
    ) external view returns (IHorizonStakingTypes.DelegationPool memory);

    function getDelegation(
        address delegator,
        address serviceProvider,
        address verifier
    ) external view returns (IHorizonStakingTypes.Delegation memory);

    function getThawRequest(bytes32 thawRequestId) external view returns (IHorizonStakingTypes.ThawRequest memory);

    function getProvision(
        address serviceProvider,
        address verifier
    ) external view returns (IHorizonStakingTypes.Provision memory);

    function getDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType
    ) external view returns (uint256);

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) external view returns (uint256 tokens);

    function getProviderTokensAvailable(address serviceProvider, address verifier) external view returns (uint256);
}
