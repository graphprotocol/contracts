// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PROVIDER
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCancelTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Cancel(FuzzyTestAccept calldata fuzzyTestAccept, uint8 unboundedCanceler) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestAccept
        );

        if (_fuzzyCancelByPayer(unboundedCanceler)) {
            _cancelByPayer(acceptedRca, agreementId);
        } else {
            _cancelByProvider(acceptedRca, agreementId);
        }
    }

    function test_Cancel_Revert_WhenNoneState(IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA) public {
        vm.assume(fuzzyRCA.payer != address(0));
        vm.assume(fuzzyRCA.payer != _proxyAdmin);
        // Agreement doesn't exist — payer field is address(0), so auth fails
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            fuzzyRCA.payer,
            fuzzyRCA.dataService,
            fuzzyRCA.serviceProvider,
            fuzzyRCA.deadline,
            fuzzyRCA.nonce
        );

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.UnauthorizedCaller.selector, fuzzyRCA.payer, address(0))
        );
        vm.prank(fuzzyRCA.payer);
        _recurringCollector.cancel(agreementId, bytes32(0), 0);
    }

    function test_Cancel_Revert_WhenNotAuthorized(
        FuzzyTestAccept calldata fuzzyTestAccept,
        address notAuthorized
    ) public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestAccept
        );
        vm.assume(notAuthorized != rca.dataService);
        vm.assume(notAuthorized != rca.payer);
        vm.assume(notAuthorized != rca.serviceProvider);
        vm.assume(notAuthorized != _proxyAdmin);

        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.UnauthorizedCaller.selector,
            notAuthorized,
            address(0)
        );
        vm.expectRevert(expectedErr);
        vm.prank(notAuthorized);
        _recurringCollector.cancel(agreementId, activeHash, 0);
    }
    function test_Cancel_ByProvider_AllowsFinalCollection() public {
        // Setup: Create agreement with known parameters
        IRecurringCollector.RecurringCollectionAgreement memory rca;
        rca.deadline = uint64(block.timestamp + 1000);
        rca.endsAt = uint64(block.timestamp + 100_000);
        rca.payer = address(0x123);
        rca.dataService = address(0x456);
        rca.serviceProvider = address(0x789);
        rca.maxInitialTokens = 0;
        rca.maxOngoingTokensPerSecond = 1 ether;
        rca.minSecondsPerCollection = 60;
        rca.maxSecondsPerCollection = 3600;
        rca.nonce = 1;
        rca.metadata = "";

        bytes16 agreementId = _accept(rca);

        // First collection to establish lastCollectionAt
        skip(rca.minSecondsPerCollection);
        IRecurringCollector.CollectParams memory firstCollect = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: keccak256("first"),
            tokens: 1 ether,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, _generateCollectData(firstCollect));

        // Provider works for minSecondsPerCollection more, then cancels
        skip(rca.minSecondsPerCollection);
        bytes32 vHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.cancel(agreementId, vHash, 0);

        // State should NOT be SETTLED yet — data service needs to do a final collection
        IRecurringCollector.AgreementData memory data = _recurringCollector.getAgreementData(agreementId);
        assertTrue(data.state & SETTLED == 0, "agreement should not be SETTLED immediately on provider cancel");
        assertTrue(data.state & NOTICE_GIVEN != 0, "agreement should have NOTICE_GIVEN");
        assertTrue(data.state & BY_PROVIDER != 0, "agreement should have BY_PROVIDER");

        // Data service should be able to collect for the work done since lastCollectionAt
        uint256 expectedTokens = rca.maxOngoingTokensPerSecond * rca.minSecondsPerCollection;
        IRecurringCollector.CollectParams memory finalCollect = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: keccak256("final"),
            tokens: expectedTokens,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(
            IGraphPayments.PaymentTypes.IndexingFee,
            _generateCollectData(finalCollect)
        );
        assertEq(collected, expectedTokens, "data service should collect for work done before provider cancel");

        // After final collection, agreement should auto-settle
        data = _recurringCollector.getAgreementData(agreementId);
        assertTrue(data.state & SETTLED != 0, "agreement should be SETTLED after final collection");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
