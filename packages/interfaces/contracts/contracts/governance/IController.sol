// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

interface IController {
    function getGovernor() external view returns (address);

    // -- Registry --

    function setContractProxy(bytes32 id, address contractAddress) external;

    function unsetContractProxy(bytes32 id) external;

    function updateController(bytes32 id, address controller) external;

    function getContractProxy(bytes32 id) external view returns (address);

    // -- Pausing --

    function setPartialPaused(bool partialPaused) external;

    function setPaused(bool paused) external;

    function setPauseGuardian(address newPauseGuardian) external;

    function paused() external view returns (bool);

    function partialPaused() external view returns (bool);
}
