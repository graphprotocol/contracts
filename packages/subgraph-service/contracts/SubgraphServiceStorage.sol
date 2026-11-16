// SPDX-License-Identifier: GPL-3.0-or-later

// solhint-disable one-contract-per-file

pragma solidity ^0.8.27;

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

/**
 * @title SubgraphServiceV1Storage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the Subgraph Service contract
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract SubgraphServiceV1Storage is ISubgraphService {
    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public override indexers;

    ///@notice Multiplier for how many tokens back collected query fees
    uint256 public override stakeToFeesRatio;

    /// @notice The cut curators take from query fee payments. In PPM.
    uint256 public override curationFeesCut;

    /// @notice Destination of indexer payments
    mapping(address indexer => address destination) public override paymentsDestination;

    /// @notice The cut data service takes from indexing fee payments. In PPM.
    uint256 public indexingFeesCut;
}

/**
 * @title SubgraphServiceV2Storage
 * @author Edge & Node
 * @notice Adds allocation close guard.
 */
abstract contract SubgraphServiceV2Storage is SubgraphServiceV1Storage {
    /// @notice When true, closing an allocation that has an active indexing agreement will revert.
    bool internal blockClosingAllocationWithActiveAgreement;
}

/**
 * @title SubgraphServiceV3Storage
 * @author Edge & Node
 * @notice Adds the gateway cut taken from query fee payments.
 */
abstract contract SubgraphServiceV3Storage is SubgraphServiceV2Storage {
    /// @notice The cut the protocol takes from every query fee payment, whoever the payer is. In PPM.
    uint256 public override gatewayCut;

    /// @notice The address the gateway cut is sent to
    address public override gatewayCutDestination;
}
