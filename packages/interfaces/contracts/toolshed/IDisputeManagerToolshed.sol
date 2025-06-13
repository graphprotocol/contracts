// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import { IDisputeManager } from "../subgraph-service/IDisputeManager.sol";
import { IOwnable } from "../subgraph-service/internal/IOwnable.sol";

interface IDisputeManagerToolshed is IDisputeManager, IOwnable {
    /**
     * @notice Get the dispute period.
     * @return Dispute period in seconds
     */
    function disputePeriod() external view returns (uint64);

    /**
     * @notice Get the fisherman reward cut.
     * @return Fisherman reward cut in percentage (ppm)
     */
    function fishermanRewardCut() external view returns (uint32);

    /**
     * @notice Get the maximum percentage that can be used for slashing indexers.
     * @return Max percentage slashing for disputes
     */
    function maxSlashingCut() external view returns (uint32);

    /**
     * @notice Get the dispute deposit.
     * @return Dispute deposit
     */
    function disputeDeposit() external view returns (uint256);

    /**
     * @notice Get the subgraph service address.
     * @return Subgraph service address
     */
    function subgraphService() external view returns (address);

    /**
     * @notice Get the arbitrator address.
     * @return Arbitrator address
     */
    function arbitrator() external view returns (address);

    /**
     * @notice Get the dispute status.
     * @param disputeId The dispute ID
     * @return Dispute status
     */
    function disputes(bytes32 disputeId) external view returns (IDisputeManager.Dispute memory);
}
