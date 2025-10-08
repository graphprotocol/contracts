// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title DirectAllocation
 * @author Edge & Node
 * @notice A simple contract that receives tokens from the IssuanceAllocator and allows
 * an authorized operator to withdraw them.
 *
 * @dev This contract is designed to be a non-self-minting target in the IssuanceAllocator.
 * The IssuanceAllocator will mint tokens directly to this contract, and the authorized
 * operator can send them to individual addresses as needed.
 *
 * This contract is pausable by the PAUSE_ROLE. When paused, tokens cannot be sent.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract DirectAllocation is BaseUpgradeable, IIssuanceTarget {
    // -- Events --

    /// @notice Emitted when tokens are sent
    /// @param to The address that received the tokens
    /// @param amount The amount of tokens sent
    event TokensSent(address indexed to, uint256 amount); // solhint-disable-line gas-indexed-events
    // Do not need to index amount, ignoring gas-indexed-events warning.

    /// @notice Emitted before the issuance allocation changes
    event BeforeIssuanceAllocationChange();

    // -- Constructor --

    /**
     * @notice Constructor for the DirectAllocation contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param graphToken Address of the Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address graphToken) BaseUpgradeable(graphToken) {}

    // -- Initialization --

    /**
     * @notice Initialize the DirectAllocation contract
     * @param governor Address that will have the GOVERNOR_ROLE
     */
    function initialize(address governor) external virtual initializer {
        __BaseUpgradeable_init(governor);
    }

    // -- ERC165 --

    /**
     * @inheritdoc ERC165Upgradeable
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIssuanceTarget).interfaceId || super.supportsInterface(interfaceId);
    }

    // -- External Functions --

    /**
     * @notice Send tokens to a specified address
     * @dev This function can only be called by accounts with the OPERATOR_ROLE
     * @param to Address to send tokens to
     * @param amount Amount of tokens to send
     */
    function sendTokens(address to, uint256 amount) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        // TODO: missed for audit, should change to custom error in furture
        // solhint-disable-next-line gas-custom-errors
        require(GRAPH_TOKEN.transfer(to, amount), "!transfer");
        emit TokensSent(to, amount);
    }

    /**
     * @dev For DirectAllocation, this is a no-op since we don't need to perform any calculations
     * before an allocation change. We simply receive tokens from the IssuanceAllocator.
     * @inheritdoc IIssuanceTarget
     */
    function beforeIssuanceAllocationChange() external virtual override {
        emit BeforeIssuanceAllocationChange();
    }

    /**
     * @inheritdoc IIssuanceTarget
     */
    function setIssuanceAllocator(address issuanceAllocator) external virtual override onlyRole(GOVERNOR_ROLE) {
        // No-op for DirectAllocation
        // This contract doesn't need to store the issuance allocator
    }
}
