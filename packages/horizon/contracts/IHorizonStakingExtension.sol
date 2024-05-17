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

    function getStake(address serviceProvider) external view returns (uint256);

    function getDelegatedTokensAvailable(address _serviceProvider, address _verifier) external view returns (uint256);
    function getTokensAvailable(address _serviceProvider, address _verifier) external view returns (uint256);

    function getServiceProvider(
        address serviceProvider
    ) external view returns (IHorizonStakingTypes.ServiceProvider memory);

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param _operator Address to authorize or unauthorize
     * @param _verifier The verifier / data service on which they'll be allowed to operate
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, address _verifier, bool _allowed) external;

    // for vesting contracts
    function setOperatorLocked(address _operator, address _verifier, bool _allowed) external;

    function getMaxThawingPeriod() external view returns (uint64);

    function getDelegationPool(
        address _serviceProvider,
        address _verifier
    ) external view returns (IHorizonStakingTypes.DelegationPool memory);
    function getDelegation(
        address _delegator,
        address _serviceProvider,
        address _verifier
    ) external view returns (IHorizonStakingTypes.Delegation memory);
    function getThawRequest(bytes32 _thawRequestId) external view returns (IHorizonStakingTypes.ThawRequest memory);
    function getProvision(
        address _serviceProvider,
        address _verifier
    ) external view returns (IHorizonStakingTypes.Provision memory);

    function setDelegationFeeCut(
        address _serviceProvider,
        address _verifier,
        uint256 _feeType,
        uint256 _feeCut
    ) external;

    function getDelegationFeeCut(
        address _serviceProvider,
        address _verifier,
        uint256 _feeType
    ) external view returns (uint256);
}
