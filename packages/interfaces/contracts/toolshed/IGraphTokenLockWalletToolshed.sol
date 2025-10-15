// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

// solhint-disable use-natspec

import { IGraphTokenLockWallet } from "../token-distribution/IGraphTokenLockWallet.sol";
import { IGraphPayments } from "../horizon/IGraphPayments.sol";

/**
 * @title IGraphTokenLockWalletToolshed
 * @author Edge & Node
 * @notice Extended interface for GraphTokenLockWallet that includes Horizon protocol interaction functions
 * @dev Functions included are based on the GraphTokenLockManager whitelist for vesting contracts on Horizon
 */
interface IGraphTokenLockWalletToolshed is IGraphTokenLockWallet {
    // === STAKE MANAGEMENT ===
    function stake(uint256 tokens) external;
    function unstake(uint256 tokens) external;
    function withdraw() external;

    // === PROVISION MANAGEMENT ===
    function provisionLocked(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external;
    function thaw(address serviceProvider, address verifier, uint256 tokens) external returns (bytes32);
    function deprovision(address serviceProvider, address verifier, uint256 nThawRequests) external;

    // === PROVISION CONFIGURATION ===
    function setOperatorLocked(address verifier, address operator, bool allowed) external;
    function setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType,
        uint256 feeCut
    ) external;
    function setRewardsDestination(address serviceProvider, address rewardsDestination) external;

    // === DELEGATION MANAGEMENT ===
    function delegate(address serviceProvider, uint256 tokens) external;
    function undelegate(address serviceProvider, uint256 shares) external;
    function withdrawDelegated(address serviceProvider, address verifier, uint256 nThawRequests) external;

    // === LEGACY DELEGATION MANAGEMENT ===
    function withdrawDelegated(address indexer, address __DEPRECATED_delegateToIndexer) external returns (uint256);
}
