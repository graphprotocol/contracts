// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IController } from "@graphprotocol/interfaces/contracts/contracts/governance/IController.sol";

/// @notice Minimal Controller stub for GraphDirectory consumers.
/// Returns registered addresses; unregistered names return a dummy nonzero address
/// so GraphDirectory constructors don't revert on zero-address checks.
contract ControllerStub is IController {
    mapping(bytes32 => address) private _registry;
    address private immutable _dummy;

    constructor() {
        _dummy = address(uint160(uint256(keccak256("ControllerStub.dummy"))));
    }

    function register(string memory name, address addr) external {
        _registry[keccak256(abi.encodePacked(name))] = addr;
    }

    function getContractProxy(bytes32 id) external view override returns (address) {
        address a = _registry[id];
        return a != address(0) ? a : _dummy;
    }

    // -- Stubs --
    function getGovernor() external pure override returns (address) {
        return address(1);
    }
    function paused() external pure override returns (bool) {
        return false;
    }
    function partialPaused() external pure override returns (bool) {
        return false;
    }
    function setContractProxy(bytes32, address) external override {}
    function unsetContractProxy(bytes32) external override {}
    function updateController(bytes32, address) external override {}
    function setPartialPaused(bool) external override {}
    function setPaused(bool) external override {}
    function setPauseGuardian(address) external override {}
}
