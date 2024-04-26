// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.9.0;
pragma abicoder v2;

import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";

interface IHorizonStakingExtension {
    /**
     * @dev Emitted when serviceProvider allows a verifier
     */
    event VerifierAllowed(address indexed serviceProvider, address indexed verifier);

    /**
     * @dev Emitted when serviceProvider denies a verifier
     */
    event VerifierDenied(address indexed serviceProvider, address indexed verifier);

    /**
     * @dev Emitted when a global operator (for all data services) is allowed or denied by a service provider
     */
    event GlobalOperatorSet(address indexed serviceProvider, address indexed operator, bool allowed);

    /**
     * @dev Emitted when an operator is allowed or denied by a service provider for a particular data service
     */
    event OperatorSet(address indexed serviceProvider, address indexed operator, address verifier, bool allowed);

    function getStake(address serviceProvider) external view returns (uint256);

    function getDelegatedTokensAvailable(address _serviceProvider, address _verifier) external view returns (uint256);

    function getTokensAvailable(address _serviceProvider, address _verifier) external view returns (uint256);

    function getServiceProvider(
        address serviceProvider
    ) external view returns (IHorizonStakingTypes.ServiceProvider memory);

    function allowVerifier(address _verifier) external;

    /**
     * @notice Deny a verifier for stake provisions.
     * After calling this, the service provider will immediately
     * be unable to provision any stake to the verifier.
     * Any existing provisions will be unaffected.
     * @param _verifier The address of the contract that can slash the provision
     */
    function denyVerifier(address _verifier) external;

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on all data services.
     * @param _operator Address to authorize or unauthorize
     * @param _allowed Whether the operator is authorized or not
     */
    function setGlobalOperator(address _operator, bool _allowed) external;

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param _operator Address to authorize or unauthorize
     * @param _verifier The verifier / data service on which they'll be allowed to operate
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, address _verifier, bool _allowed) external;

    function isAllowedVerifier(address _serviceProvider, address _verifier) external view returns (bool);

    function getMaxThawingPeriod() external view returns (uint64);
}
