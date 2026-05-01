// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { IndexingAgreement } from "../../../contracts/libraries/IndexingAgreement.sol";
import { Directory } from "../../../contracts/utilities/Directory.sol";

contract IndexingAgreementTest is Test {
    IndexingAgreement.StorageManager private _storageManager;
    address private _mockCollector;

    function setUp() public {
        _mockCollector = makeAddr("mockCollector");
    }

    function test_IndexingAgreement_Get(bytes16 agreementId) public {
        vm.assume(agreementId != bytes16(0));

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(Directory.recurringCollector.selector),
            abi.encode(IRecurringCollector(_mockCollector))
        );

        IRecurringCollector.AgreementData memory collectorAgreement;
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreement.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        vm.expectRevert(abi.encodeWithSelector(IndexingAgreement.IndexingAgreementNotActive.selector, agreementId));
        IndexingAgreement.get(_storageManager, agreementId);

        collectorAgreement.dataService = address(this);
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreement.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        IIndexingAgreement.AgreementWrapper memory wrapper = IndexingAgreement.get(_storageManager, agreementId);
        assertEq(wrapper.collectorAgreement.dataService, address(this));
    }

    function test_IndexingAgreement_OnCloseAllocation_NoAgreement(address allocationId) public {
        vm.assume(allocationId != address(0));
        // No active agreement — returns early regardless of blockIfActive
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, true);
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, false);
    }

    function test_IndexingAgreement_OnCloseAllocation_InactiveAgreement(
        bytes16 agreementId,
        address allocationId
    ) public {
        vm.assume(agreementId != bytes16(0));
        vm.assume(allocationId != address(0));

        _storageManager.allocationToActiveAgreementId[allocationId] = agreementId;

        // Collector agreement not active (default state = NotAccepted) — returns early
        IRecurringCollector.AgreementData memory collectorAgreement;

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(Directory.recurringCollector.selector),
            abi.encode(IRecurringCollector(_mockCollector))
        );
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreement.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        // Should not revert even with blockIfActive=true since agreement is not active
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, true);
    }

    function test_IndexingAgreement_OnCloseAllocation_RevertsWhenActiveAndBlocked(
        bytes16 agreementId,
        address allocationId
    ) public {
        vm.assume(agreementId != bytes16(0));
        vm.assume(allocationId != address(0));

        _storageManager.allocationToActiveAgreementId[allocationId] = agreementId;
        _storageManager.agreements[agreementId] = IIndexingAgreement.State({
            allocationId: allocationId,
            version: IIndexingAgreement.IndexingAgreementVersion.V1
        });

        IRecurringCollector.AgreementData memory collectorAgreement;
        collectorAgreement.dataService = address(this);
        collectorAgreement.state = IRecurringCollector.AgreementState.Accepted;

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(Directory.recurringCollector.selector),
            abi.encode(IRecurringCollector(_mockCollector))
        );
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreement.selector, agreementId),
            abi.encode(collectorAgreement)
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

    function test_IndexingAgreement_OnCloseAllocation_CancelsWhenActiveAndNotBlocked(
        bytes16 agreementId,
        address allocationId
    ) public {
        vm.assume(agreementId != bytes16(0));
        vm.assume(allocationId != address(0));

        _storageManager.allocationToActiveAgreementId[allocationId] = agreementId;
        _storageManager.agreements[agreementId] = IIndexingAgreement.State({
            allocationId: allocationId,
            version: IIndexingAgreement.IndexingAgreementVersion.V1
        });

        IRecurringCollector.AgreementData memory collectorAgreement;
        collectorAgreement.dataService = address(this);
        collectorAgreement.state = IRecurringCollector.AgreementState.Accepted;

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(Directory.recurringCollector.selector),
            abi.encode(IRecurringCollector(_mockCollector))
        );
        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreement.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        vm.expectCall(_mockCollector, abi.encodeWithSelector(IRecurringCollector.cancel.selector, agreementId));
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, false);
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
