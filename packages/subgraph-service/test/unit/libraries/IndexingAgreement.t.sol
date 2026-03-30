// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import {
    IAgreementCollector,
    REGISTERED,
    ACCEPTED,
    SETTLED,
    NOTICE_GIVEN,
    BY_PROVIDER
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IndexingAgreement } from "../../../contracts/libraries/IndexingAgreement.sol";

contract IndexingAgreementTest is Test {
    IndexingAgreement.StorageManager private _storageManager;
    address private _mockCollector;

    function setUp() public {
        _mockCollector = makeAddr("mockCollector");
    }

    function test_IndexingAgreement_Get(bytes16 agreementId) public {
        vm.assume(agreementId != bytes16(0));

        // Set the collector in the agreement state so _get() can resolve it
        _storageManager.agreements[agreementId] = IIndexingAgreement.State({
            allocationId: address(0),
            collector: _mockCollector,
            version: IIndexingAgreement.IndexingAgreementVersion.V1,
            subgraphDeploymentId: bytes32(0)
        });

        IRecurringCollector.AgreementData memory collectorAgreement;
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreementData.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        vm.expectRevert(abi.encodeWithSelector(IndexingAgreement.IndexingAgreementNotActive.selector, agreementId));
        IndexingAgreement.get(_storageManager, agreementId);

        collectorAgreement.dataService = address(this);
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreementData.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        IIndexingAgreement.AgreementWrapper memory wrapper = IndexingAgreement.get(_storageManager, agreementId);
        assertEq(wrapper.collectorAgreement.dataService, address(this));
    }

    function test_IndexingAgreement_OnCloseAllocation_NoAgreement(address allocationId) public {
        vm.assume(allocationId != address(0));
        // No active agreement — returns early
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, true);
    }

    function test_IndexingAgreement_OnCloseAllocation_RevertsWhenNotSettled(
        bytes16 agreementId,
        address allocationId
    ) public {
        vm.assume(agreementId != bytes16(0));
        vm.assume(allocationId != address(0));

        _storageManager.allocationToActiveAgreementId[allocationId] = agreementId;
        _storageManager.agreements[agreementId] = IIndexingAgreement.State({
            allocationId: allocationId,
            collector: _mockCollector,
            version: IIndexingAgreement.IndexingAgreementVersion.V1,
            subgraphDeploymentId: bytes32(0)
        });

        // Mock collector returning REGISTERED | ACCEPTED (not SETTLED)
        uint16 notSettledState = REGISTERED | ACCEPTED;
        IAgreementCollector.AgreementVersion memory version = IAgreementCollector.AgreementVersion({
            agreementId: agreementId,
            versionHash: bytes32(uint256(1)),
            state: notSettledState
        });
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IAgreementCollector.getAgreementVersionAt.selector, agreementId, 0),
            abi.encode(version)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationHasActiveAgreement.selector,
                allocationId,
                agreementId
            )
        );
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, true);
    }

    function test_IndexingAgreement_OnCloseAllocation_SucceedsWhenSettled(
        bytes16 agreementId,
        address allocationId
    ) public {
        vm.assume(agreementId != bytes16(0));
        vm.assume(allocationId != address(0));

        _storageManager.allocationToActiveAgreementId[allocationId] = agreementId;
        _storageManager.agreements[agreementId] = IIndexingAgreement.State({
            allocationId: allocationId,
            collector: _mockCollector,
            version: IIndexingAgreement.IndexingAgreementVersion.V1,
            subgraphDeploymentId: bytes32(0)
        });

        // Mock collector returning SETTLED state
        uint16 settledState = REGISTERED | ACCEPTED | NOTICE_GIVEN | SETTLED | BY_PROVIDER;
        IAgreementCollector.AgreementVersion memory version = IAgreementCollector.AgreementVersion({
            agreementId: agreementId,
            versionHash: bytes32(uint256(1)),
            state: settledState
        });
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IAgreementCollector.getAgreementVersionAt.selector, agreementId, 0),
            abi.encode(version)
        );

        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, true);

        // Both sides of mapping should be cleared
        assertEq(_storageManager.allocationToActiveAgreementId[allocationId], bytes16(0));
        assertEq(_storageManager.agreements[agreementId].allocationId, address(0));
    }

    function test_IndexingAgreement_StorageManagerLocation() public pure {
        assertEq(
            IndexingAgreement.INDEXING_AGREEMENT_STORAGE_MANAGER_LOCATION,
            keccak256(
                abi.encode(
                    uint256(keccak256("graphprotocol.subgraph-service.storage.StorageManager.IndexingAgreement")) - 1
                )
            ) & ~bytes32(uint256(0xff))
        );
    }
}
