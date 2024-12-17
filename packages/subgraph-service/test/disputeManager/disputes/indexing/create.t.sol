// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingCreateDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Indexing_Create_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        _createIndexingDispute(allocationID, bytes32("POI1"));
    }

    function test_Indexing_Create_Dispute_RevertWhen_SubgraphServiceNotSet(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);

        // clear subgraph service address from storage
        _setStorage_SubgraphService(address(0));

        // // Approve the dispute deposit
        token.approve(address(disputeManager), disputeDeposit);

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerSubgraphServiceNotSet.selector));
        disputeManager.createIndexingDispute(allocationID, bytes32("POI2"));
    }

    function test_Indexing_Create_MultipleDisputes() public {
        uint256 tokens = 10000 ether;
        uint8 numIndexers = 10;
        uint256[] memory allocationIDPrivateKeys = new uint256[](numIndexers);
        for (uint i = 0; i < numIndexers; i++) {
            string memory indexerName = string(abi.encodePacked("Indexer ", i));
            address indexer = createUser(indexerName);
            vm.assume(indexer != address(0));

            resetPrank(indexer);
            mint(indexer, tokens);
            _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);
            _register(indexer, abi.encode("url", "geoHash", address(0)));
            uint256 allocationIDPrivateKey = uint256(keccak256(abi.encodePacked(i)));
            bytes memory data = _createSubgraphAllocationData(
                indexer,
                subgraphDeployment,
                allocationIDPrivateKey,
                tokens
            );
            _startService(indexer, data);
            allocationIDPrivateKeys[i] = allocationIDPrivateKey;
        }

        resetPrank(users.fisherman);
        for (uint i = 0; i < allocationIDPrivateKeys.length; i++) {
            _createIndexingDispute(vm.addr(allocationIDPrivateKeys[i]), bytes32("POI1"));
        }
    }

    function test_Indexing_Create_RevertWhen_DisputeAlreadyCreated(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // Create another dispute with different fisherman
        address otherFisherman = makeAddr("otherFisherman");
        resetPrank(otherFisherman);
        mint(otherFisherman, disputeDeposit);
        token.approve(address(disputeManager), disputeDeposit);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerDisputeAlreadyCreated.selector,
            disputeID
        );
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, bytes32("POI1"));
        vm.stopPrank();
    }

    function test_Indexing_Create_RevertIf_DepositUnderMinimum(uint256 tokensDeposit) public useFisherman {
        tokensDeposit = bound(tokensDeposit, 0, disputeDeposit - 1);
        token.approve(address(disputeManager), tokensDeposit);
        bytes memory expectedError = abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)",
            address(disputeManager),
            tokensDeposit,
            disputeDeposit
        );
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, bytes32("POI3"));
        vm.stopPrank();
    }

    function test_Indexing_Create_RevertIf_AllocationDoesNotExist(uint256 tokens) public useFisherman {
        tokens = bound(tokens, disputeDeposit, 10_000_000_000 ether);
        token.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerIndexerNotFound.selector,
            allocationID
        );
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, bytes32("POI4"));
        vm.stopPrank();
    }

    function test_Indexing_Create_RevertIf_IndexerIsBelowStake(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Close allocation
        bytes memory data = abi.encode(allocationID);
        _stopService(users.indexer, data);
        // Thaw, deprovision and unstake
        address subgraphDataServiceAddress = address(subgraphService);
        _thawDeprovisionAndUnstake(users.indexer, subgraphDataServiceAddress, tokens);

        // Attempt to create dispute
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerZeroTokens.selector));
        disputeManager.createIndexingDispute(allocationID, bytes32("POI1"));
    }
}
