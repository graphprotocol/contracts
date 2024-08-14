// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract SubgraphServiceTest is SubgraphServiceSharedTest {
    using PPMMath for uint256;

    /*
     * VARIABLES
     */

    /*
     * MODIFIERS
     */

    modifier useOperator {
        vm.startPrank(users.operator);
        _;
        vm.stopPrank();
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
    }

    /*
     * HELPERS
     */

    function _createAndStartAllocation(address _indexer, uint256 _tokens) internal {
        mint(_indexer, _tokens);

        resetPrank(_indexer);
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
        staking.provision(_indexer, address(subgraphService), _tokens, maxSlashingPercentage, disputePeriod);
        subgraphService.register(_indexer, abi.encode("url", "geoHash", address(0)));

        (address newIndexerAllocationId, uint256 newIndexerAllocationKey) = makeAddrAndKey("newIndexerAllocationId");
        bytes32 digest = subgraphService.encodeAllocationProof(_indexer, newIndexerAllocationId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newIndexerAllocationKey, digest);

        bytes memory data = abi.encode(subgraphDeployment, _tokens, newIndexerAllocationId, abi.encodePacked(r, s, v));
        subgraphService.startService(_indexer, data);
    }

    function _stopAllocation(address _indexer, address _allocationID) internal {
        resetPrank(_indexer);
        assertTrue(subgraphService.isActiveAllocation(_allocationID));
        bytes memory data = abi.encode(_allocationID);
        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceStopped(_indexer, data);
        subgraphService.stopService(_indexer, data);

        uint256 subgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(subgraphDeployment);
        assertEq(subgraphAllocatedTokens, 0);
    }

    function _collectIndexingRewards(address _indexer, address _allocationID, uint256 _tokens) internal {
        resetPrank(_indexer);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(_allocationID, bytes32("POI1"));

        uint256 indexerPreviousProvisionBalance = staking.getProviderTokensAvailable(_indexer, address(subgraphService));
        subgraphService.collect(_indexer, paymentType, data);

        uint256 indexerProvisionBalance = staking.getProviderTokensAvailable(_indexer, address(subgraphService));
        assertEq(indexerProvisionBalance, indexerPreviousProvisionBalance + _tokens.mulPPM(rewardsPerSignal));
    }
}
