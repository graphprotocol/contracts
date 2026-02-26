// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
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

    function test_IndexingAgreement_OnCloseAllocation(bytes16 agreementId, address allocationId, bool stale) public {
        vm.assume(agreementId != bytes16(0));
        vm.assume(allocationId != address(0));

        delete _storageManager;
        vm.clearMockedCalls();

        // No active agreement for allocation ID, returns early, no assertions needed
        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, stale);

        // Active agreement for allocation ID, but collector agreement is not set, returns early, no assertions needed
        _storageManager.allocationToActiveAgreementId[allocationId] = agreementId;

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

        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, stale);

        // Active agreement for allocation ID, collector agreement is set, should cancel the agreement
        collectorAgreement.dataService = address(this);
        collectorAgreement.state = IRecurringCollector.AgreementState.Accepted;

        _storageManager.agreements[agreementId] = IIndexingAgreement.State({
            allocationId: allocationId,
            version: IIndexingAgreement.IndexingAgreementVersion.V1
        });

        vm.mockCall(
            _mockCollector,
            abi.encodeWithSelector(IRecurringCollector.getAgreement.selector, agreementId),
            abi.encode(collectorAgreement)
        );

        vm.expectCall(_mockCollector, abi.encodeWithSelector(IRecurringCollector.cancel.selector, agreementId));

        IndexingAgreement.onCloseAllocation(_storageManager, allocationId, stale);
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
