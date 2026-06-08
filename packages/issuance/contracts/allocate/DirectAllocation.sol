// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { ISendTokens } from "@graphprotocol/interfaces/contracts/issuance/allocate/ISendTokens.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { IGraphToken } from "../common/IGraphToken.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title DirectAllocation
 * @author Edge & Node
 * @notice A simple contract that receives tokens from the IssuanceAllocator and allows
 * an authorized operator to withdraw them.
 *
 * @dev This contract is designed to be an allocator-minting target in the IssuanceAllocator.
 * The IssuanceAllocator will mint tokens directly to this contract, and the authorized
 * operator can send them to individual addresses as needed.
 *
 * This contract is pausable by the PAUSE_ROLE. When paused, tokens cannot be sent.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract DirectAllocation is BaseUpgradeable, IIssuanceTarget, ISendTokens {
    // -- Namespaced Storage --

    /// @notice ERC-7201 storage location for DirectAllocation
    bytes32 private constant DIRECT_ALLOCATION_STORAGE_LOCATION =
        // solhint-disable-next-line gas-small-strings
        keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.DirectAllocation")) - 1)) &
            ~bytes32(uint256(0xff));

    /// @notice Main storage structure for DirectAllocation using ERC-7201 namespaced storage
    /// @param issuanceAllocator The issuance allocator that distributes tokens to this contract
    /// @custom:storage-location erc7201:graphprotocol.storage.DirectAllocation
    struct DirectAllocationData {
        IIssuanceAllocationDistribution issuanceAllocator;
    }

    /**
     * @notice Returns the storage struct for DirectAllocation
     * @return $ contract storage
     */
    function _getDirectAllocationStorage() private pure returns (DirectAllocationData storage $) {
        // solhint-disable-previous-line use-natspec
        // Solhint does not support $ return variable in natspec

        bytes32 slot = DIRECT_ALLOCATION_STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -- Custom Errors --

    /// @notice Thrown when token transfer fails
    /// @param to The address that the transfer was attempted to
    /// @param amount The amount of tokens that failed to transfer
    error SendTokensFailed(address to, uint256 amount);

    /// @notice Thrown when the issuance allocator does not support IIssuanceAllocationDistribution
    /// @param allocator The rejected allocator address
    error InvalidIssuanceAllocator(address allocator);

    // -- Events --

    /// @notice Emitted when tokens are sent
    /// @param to The address that received the tokens
    /// @param amount The amount of tokens sent
    event TokensSent(address indexed to, uint256 indexed amount);
    // Do not need to index amount, ignoring gas-indexed-events warning.

    // -- Constructor --

    /**
     * @notice Constructor for the DirectAllocation contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param graphToken The Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(IGraphToken graphToken) BaseUpgradeable(graphToken) {}

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
        return
            interfaceId == type(IIssuanceTarget).interfaceId ||
            interfaceId == type(ISendTokens).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // -- External Functions --

    /**
     * @inheritdoc ISendTokens
     */
    function sendTokens(address to, uint256 amount) external override onlyRole(OPERATOR_ROLE) whenNotPaused {
        require(GRAPH_TOKEN.transfer(to, amount), SendTokensFailed(to, amount));
        emit TokensSent(to, amount);
    }

    /**
     * @dev For DirectAllocation, this is a no-op since we don't need to perform any calculations
     * before an allocation change. We simply receive tokens from the IssuanceAllocator.
     * @inheritdoc IIssuanceTarget
     */
    function beforeIssuanceAllocationChange() external virtual override {}

    /// @inheritdoc IIssuanceTarget
    function getIssuanceAllocator() external view virtual override returns (IIssuanceAllocationDistribution) {
        return _getDirectAllocationStorage().issuanceAllocator;
    }

    /// @inheritdoc IIssuanceTarget
    function setIssuanceAllocator(
        IIssuanceAllocationDistribution newIssuanceAllocator
    ) external virtual override onlyRole(GOVERNOR_ROLE) {
        DirectAllocationData storage $ = _getDirectAllocationStorage();
        if (address(newIssuanceAllocator) == address($.issuanceAllocator)) return;

        if (address(newIssuanceAllocator) != address(0))
            require(
                ERC165Checker.supportsInterface(
                    address(newIssuanceAllocator),
                    type(IIssuanceAllocationDistribution).interfaceId
                ),
                InvalidIssuanceAllocator(address(newIssuanceAllocator))
            );

        emit IssuanceAllocatorSet($.issuanceAllocator, newIssuanceAllocator);
        $.issuanceAllocator = newIssuanceAllocator;
    }
}
