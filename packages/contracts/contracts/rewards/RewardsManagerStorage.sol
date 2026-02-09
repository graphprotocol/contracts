// SPDX-License-Identifier: GPL-2.0-or-later

/* solhint-disable one-contract-per-file */

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

pragma solidity ^0.7.6 || 0.8.27 || 0.8.33;

import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";
import { IRewardsIssuer } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { IRewardsManagerDeprecated } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManagerDeprecated.sol";
import { Managed } from "../governance/Managed.sol";

/**
 * @title RewardsManagerV1Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V1
 */
contract RewardsManagerV1Storage is Managed {
    // -- State --

    /// @dev Deprecated issuance rate variable (no longer used)
    uint256 private __DEPRECATED_issuanceRate; // solhint-disable-line var-name-mixedcase

    /// @notice Accumulated rewards per signal (fixed-point, scaled by 1e18)
    /// @dev Never decreases. Only increases via updateAccRewardsPerSignal().
    /// Represents the cumulative GRT rewards per signaled token since contract deployment.
    uint256 public accRewardsPerSignal;

    /// @notice Block number when accumulated rewards per signal was last updated
    /// @dev Used to calculate time delta for new reward accrual. Must be updated atomically
    /// with accRewardsPerSignal to maintain accounting consistency.
    uint256 public accRewardsPerSignalLastBlockUpdated;

    /// @notice Address of role allowed to deny rewards on subgraphs
    address public subgraphAvailabilityOracle;

    /// @notice Subgraph related rewards: subgraph deployment ID => subgraph rewards
    /// @dev Accumulation state tracked per subgraph.
    mapping(bytes32 => IRewardsManager.Subgraph) public subgraphs;

    /// @notice Subgraph denylist: subgraph deployment ID => block when added or zero (if not denied)
    /// @dev **Denial Semantics**:
    /// - Non-zero value: subgraph is denied since that block number
    /// - Zero value: subgraph is not denied
    /// - When denied: accRewardsPerAllocatedToken freezes (stops updating)
    /// - New rewards during denial are reclaimed (if reclaim address configured) or dropped
    mapping(bytes32 => uint256) public denylist;
}

/**
 * @title RewardsManagerV2Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V2
 */
contract RewardsManagerV2Storage is RewardsManagerV1Storage {
    /// @notice Minimum amount of signaled tokens on a subgraph required to accrue rewards
    uint256 public minimumSubgraphSignal;
}

/**
 * @title RewardsManagerV3Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V3
 */
contract RewardsManagerV3Storage is RewardsManagerV2Storage {
    /// @dev Deprecated token supply snapshot variable (no longer used)
    uint256 private __DEPRECATED_tokenSupplySnapshot; // solhint-disable-line var-name-mixedcase
}

/**
 * @title RewardsManagerV4Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V4
 */
abstract contract RewardsManagerV4Storage is IRewardsManagerDeprecated, RewardsManagerV3Storage {
    /// @notice GRT issued for indexer rewards per block
    /// @dev Only used when issuanceAllocator is zero address.
    uint256 public override issuancePerBlock;
}

/**
 * @title RewardsManagerV5Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V5
 */
abstract contract RewardsManagerV5Storage is IRewardsManager, RewardsManagerV4Storage {
    /// @notice Address of the subgraph service
    IRewardsIssuer public override subgraphService;
}

/**
 * @title RewardsManagerV6Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V6
 * Includes support for Rewards Eligibility Oracle, Issuance Allocator, and reclaim addresses.
 */
abstract contract RewardsManagerV6Storage is RewardsManagerV5Storage {
    /// @dev Address of the rewards eligibility oracle contract
    /// When set, indexers must pass eligibility check to claim rewards.
    /// Zero address disables eligibility checks.
    IRewardsEligibility internal rewardsEligibilityOracle;

    /// @dev Address of the issuance allocator
    /// When set, determines GRT issued per block. Zero address uses issuancePerBlock storage value.
    IIssuanceAllocationDistribution internal issuanceAllocator;

    /// @dev Mapping of reclaim reason identifiers to reclaim addresses
    /// @dev Uses bytes32 for extensibility. See RewardsCondition library for canonical reasons.
    /// **IMPORTANT**: Changes to reclaim addresses are retroactive. When an address is changed,
    /// ALL future reclaims for that reason go to the new address, regardless of when the
    /// rewards were originally accrued. Zero address means rewards are dropped (not minted).
    mapping(bytes32 => address) internal reclaimAddresses;
    /// @dev Default fallback address for reclaiming rewards when no reason-specific address is configured.
    /// Zero address means rewards are dropped (not minted) if no specific reclaim address matches.
    address internal defaultReclaimAddress;
}
