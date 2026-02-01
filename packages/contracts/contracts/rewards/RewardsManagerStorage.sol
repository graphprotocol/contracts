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
    /// @notice Accumulated rewards per signal
    uint256 public accRewardsPerSignal;
    /// @notice Block number when accumulated rewards per signal was last updated
    uint256 public accRewardsPerSignalLastBlockUpdated;

    /// @notice Address of role allowed to deny rewards on subgraphs
    address public subgraphAvailabilityOracle;

    /// @notice Subgraph related rewards: subgraph deployment ID => subgraph rewards
    mapping(bytes32 => IRewardsManager.Subgraph) public subgraphs;

    /// @notice Subgraph denylist: subgraph deployment ID => block when added or zero (if not denied)
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
    IRewardsEligibility internal rewardsEligibilityOracle;
    /// @dev Address of the issuance allocator
    IIssuanceAllocationDistribution internal issuanceAllocator;
    /// @dev Mapping of reclaim reason identifiers to reclaim addresses
    /// @dev Uses bytes32 for extensibility. See RewardsReclaim library for canonical reasons.
    mapping(bytes32 => address) internal reclaimAddresses;
}
