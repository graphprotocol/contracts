// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataServiceFees } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataServiceFees.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

interface ISubgraphService is IDataServiceFees {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
    }

    struct PaymentCuts {
        uint128 serviceCut;
        uint128 curationCut;
    }

    event QueryFeesCollected(
        address indexed serviceProvider,
        uint256 tokensCollected,
        uint256 tokensCurators,
        uint256 tokensSubgraphService
    );

    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes feeType);
    error SubgraphServiceIndexerAlreadyRegistered();
    error SubgraphServiceIndexerNotRegistered(address indexer);
    error SubgraphServiceInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokensCollected);

    function initialize(uint256 minimumProvisionTokens, uint32 maximumDelegationRatio) external;
    function resizeAllocation(address indexer, address allocationId, uint256 tokens) external;

    function migrateLegacyAllocation(address indexer, address allocationId, bytes32 subgraphDeploymentID) external;

    function setPauseGuardian(address pauseGuardian, bool allowed) external;

    function getAllocation(address allocationId) external view returns (Allocation.State memory);

    function getLegacyAllocation(address allocationId) external view returns (LegacyAllocation.State memory);

    function encodeAllocationProof(address indexer, address allocationId) external view returns (bytes32);
}
