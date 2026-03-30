// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceMultiCollectorTest is SubgraphServiceIndexingAgreementSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Unauthorized caller ====================

    function test_AcceptAgreement_RevertWhen_UnauthorizedCollector(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        address unauthorized = makeAddr("unauthorizedCollector");
        assertFalse(subgraphService.isAuthorizedCollector(unauthorized));

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceNotCollector.selector, unauthorized));
        subgraphService.acceptAgreement(
            bytes16(uint128(1)),
            bytes32(0),
            indexerState.addr,
            indexerState.addr,
            bytes(""),
            abi.encode(indexerState.allocationId)
        );
    }

    // ==================== Cross-collector identity enforcement ====================

    function test_AcceptAgreement_Update_RevertWhen_WrongCollector(Seed memory seed) public {
        // Setup: create an agreement via the real RC
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Authorize a second collector
        address collectorB = makeAddr("collectorB");
        resetPrank(users.governor);
        subgraphService.setAuthorizedCollector(collectorB, true);

        // collectorB is authorized but NOT the collector that owns this agreement
        // The library enforces collector identity: initial stores, update requires match
        resetPrank(collectorB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexingAgreement.IndexingAgreementCollectorMismatch.selector,
                agreementId,
                address(recurringCollector),
                collectorB
            )
        );
        subgraphService.acceptAgreement(agreementId, bytes32(0), address(0), indexerState.addr, bytes(""), bytes(""));
    }

    // ==================== Collector stored correctly ====================

    function test_AcceptAgreement_StoresCollector(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Verify the stored collector by reading back the agreement wrapper —
        // if the collector weren't stored, getIndexingAgreement would fail to
        // fetch collectorAgreement data from the RC.
        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(address(wrapper.agreement.collector), address(recurringCollector));
    }

    // ==================== Deauthorization ====================

    function test_DeauthorizedCollector_CannotAcceptNew(Seed memory seed) public {
        // Deauthorize the RC
        resetPrank(users.governor);
        subgraphService.setAuthorizedCollector(address(recurringCollector), false);

        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        // Build an RCA and offer it
        IRecurringCollector.RecurringCollectionAgreement memory rca = _generateAcceptableRCA(ctx, indexerState.addr);

        vm.prank(rca.payer);
        bytes16 agreementId = recurringCollector.offer(0, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        // Accept should revert because RC is no longer authorized
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceNotCollector.selector, address(recurringCollector))
        );
        vm.prank(indexerState.addr);
        recurringCollector.accept(agreementId, activeHash, abi.encode(indexerState.allocationId), 0);
    }
}
