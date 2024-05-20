// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.9.0;
pragma abicoder v2;

import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";

interface IHorizonStakingExtension {
    /**
     * @dev Emitted when an operator is allowed or denied by a service provider for a particular data service
     */
    event OperatorSet(address indexed serviceProvider, address indexed operator, address verifier, bool allowed);

    event DelegationFeeCutSet(
        address indexed serviceProvider,
        address indexed verifier,
        uint256 feeType,
        uint256 feeCut
    );

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param operator Address to authorize or unauthorize
     * @param verifier The verifier / data service on which they'll be allowed to operate
     * @param allowed Whether the operator is authorized or not
     */
    function setOperator(address operator, address verifier, bool allowed) external;

    // for vesting contracts
    function setOperatorLocked(address operator, address verifier, bool allowed) external;

    function setDelegationFeeCut(address serviceProvider, address verifier, uint256 feeType, uint256 feeCut) external;

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
        uint256 feeType
    ) external view returns (uint256);
}
