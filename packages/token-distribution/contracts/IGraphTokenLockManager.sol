// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IGraphTokenLock.sol";

interface IGraphTokenLockManager {
    // -- Factory --

    function setMasterCopy(address _masterCopy) external;

    function createTokenLockWallet(
        address _owner,
        address _beneficiary,
        uint256 _managedAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _periods,
        uint256 _releaseStartTime,
        uint256 _vestingCliffTime,
        IGraphTokenLock.Revocability _revocable
    ) external;

    // -- Funds Management --

    function token() external returns (IERC20);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    // -- Allowed Funds Destinations --

    function addTokenDestination(address _dst) external;

    function removeTokenDestination(address _dst) external;

    function isTokenDestination(address _dst) external view returns (bool);

    function getTokenDestinations() external view returns (address[] memory);

    // -- Function Call Authorization --

    function setAuthFunctionCall(string calldata _signature, address _target) external;

    function unsetAuthFunctionCall(string calldata _signature) external;

    function setAuthFunctionCallMany(string[] calldata _signatures, address[] calldata _targets) external;

    function getAuthFunctionCallTarget(bytes4 _sigHash) external view returns (address);

    function isAuthFunctionCall(bytes4 _sigHash) external view returns (bool);
}
