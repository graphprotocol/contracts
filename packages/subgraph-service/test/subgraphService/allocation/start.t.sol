// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { LegacyAllocation } from "../../../contracts/libraries/LegacyAllocation.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationStartTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_Start(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _generateData(tokens);
        _startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_AllowsZeroTokens(uint256 tokens) public  useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _generateData(0);
        _startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_ByOperator(uint256 tokens) public useOperator {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _generateData(tokens);
        _startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_NotAuthorized(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        resetPrank(users.operator);
        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.operator,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_NoValidProvision(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);
        
        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerProvisionNotFound.selector,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_NotRegistered(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);

        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            users.indexer
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_ZeroAllocationId(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, address(0));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);
        bytes memory data = abi.encode(subgraphDeployment, tokens, address(0), abi.encodePacked(r, s, v));
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerInvalidZeroAllocationId.selector
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_InvalidSignature(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        (address signer, uint256 signerPrivateKey) = makeAddrAndKey("invalidSigner");
        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerInvalidAllocationProof.selector,
            signer,
            allocationID
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_InvalidData(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, _generateRandomHexBytes(32));
        vm.expectRevert(abi.encodeWithSelector(
            ECDSA.ECDSAInvalidSignatureLength.selector,
            32
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_ArealdyExists(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes32 slot = keccak256(abi.encode(allocationID, uint256(158)));
        vm.store(address(subgraphService), slot, bytes32(uint256(uint160(users.indexer))));
        vm.store(address(subgraphService), bytes32(uint256(slot) + 1), subgraphDeployment);

        bytes memory data = _generateData(tokens);
        vm.expectRevert(abi.encodeWithSelector(
            LegacyAllocation.LegacyAllocationExists.selector,
            allocationID
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_ReusingAllocationId(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _generateData(tokens);
        _startService(users.indexer, data);

        vm.expectRevert(abi.encodeWithSelector(
            Allocation.AllocationAlreadyExists.selector,
            allocationID
        ));
        subgraphService.startService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Start_RevertWhen_NotEnoughTokens(
        uint256 tokens,
        uint256 lockTokens
    ) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS - 1);
        lockTokens = bound(lockTokens, tokens + 1, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _generateData(lockTokens);
        vm.expectRevert(abi.encodeWithSelector(
            ProvisionTracker.ProvisionTrackerInsufficientTokens.selector,
            tokens,
            lockTokens
        ));
        subgraphService.startService(users.indexer, data);
    }

    /*
     * PRIVATE FUNCTIONS
     */

    function _generateData(uint256 tokens) private view returns(bytes memory) {
        return _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIDPrivateKey, tokens);
    }

    function _generateRandomHexBytes(uint256 length) private view returns (bytes memory) {
        bytes memory randomBytes = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            randomBytes[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))) % 256));
        }
        return randomBytes;
    }
}
