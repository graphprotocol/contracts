// SPDX-License-Identifier: GPL-2.0-or-later

/* solhint-disable one-contract-per-file */

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

pragma solidity ^0.7.6 || 0.8.27;

import { IRewardsIssuer } from "./IRewardsIssuer.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
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
contract RewardsManagerV4Storage is RewardsManagerV3Storage {
    /// @notice GRT issued for indexer rewards per block
    /// @dev Only used when issuanceAllocator is zero address.
    uint256 public issuancePerBlock;
}

/**
 * @title RewardsManagerV5Storage
 * @author Edge & Node
 * @notice Storage layout for RewardsManager V5
 */
contract RewardsManagerV5Storage is RewardsManagerV4Storage {
    /// @notice Address of the subgraph service
    IRewardsIssuer public subgraphService;
}
