// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "../upgrades/GraphUpgradeable.sol";
import "../governance/Managed.sol";
import "../token/IGraphToken.sol";

/**
 * @title Bridge Escrow
 * @dev This contracts acts as a gateway for an L2 bridge (or several). It simply holds GRT and has
 * a set of spenders that can transfer the tokens; the L1 side of each L2 bridge has to be
 * approved as a spender.
 */
contract BridgeEscrow is Initializable, GraphUpgradeable, Managed {
    /**
     * @dev Initialize this contract.
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external onlyImpl initializer {
        Managed._initialize(_controller);
    }

    /**
     * @dev Approve a spender (i.e. a bridge that manages the GRT funds held by the escrow)
     * @param _spender Address of the spender that will be approved
     */
    function approveAll(address _spender) external onlyGovernor {
        graphToken().approve(_spender, type(uint256).max);
    }

    /**
     * @dev Revoke a spender (i.e. a bridge that will no longer manage the GRT funds held by the escrow)
     * @param _spender Address of the spender that will be revoked
     */
    function revokeAll(address _spender) external onlyGovernor {
        graphToken().approve(_spender, 0);
    }
}
