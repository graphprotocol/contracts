// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingBase } from "../../../contracts/interfaces/internal/IHorizonStakingBase.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";
import { MathUtils } from "../../../contracts/libraries/MathUtils.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {
    using LinkedList for LinkedList.List;
    /*
     * MODIFIERS
     */

    modifier useIndexer() {
        vm.startPrank(users.indexer);
        _;
        vm.stopPrank();
    }

    modifier useOperator() {
        vm.startPrank(users.indexer);
        staking.setOperator(users.operator, subgraphDataServiceAddress, true);
        vm.startPrank(users.operator);
        _;
        vm.stopPrank();
    }

    modifier useStake(uint256 amount) {
        vm.assume(amount > 0);
        _stake(amount);
        _;
    }

    modifier useProvision(
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) virtual {
        _useProvision(subgraphDataServiceAddress, tokens, maxVerifierCut, thawingPeriod);
        _;
    }

    modifier useProvisionDataService(
        address dataService,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) {
        _useProvision(dataService, tokens, maxVerifierCut, thawingPeriod);
        _;
    }

    modifier useDelegationFeeCut(IGraphPayments.PaymentTypes paymentType, uint256 cut) {
        _setDelegationFeeCut(paymentType, cut);
        _;
    }

    function _useProvision(address dataService, uint256 tokens, uint32 maxVerifierCut, uint64 thawingPeriod) internal {
        // use assume instead of bound to avoid the bounding falling out of scope
        vm.assume(tokens > 0);
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        vm.assume(maxVerifierCut <= MAX_MAX_VERIFIER_CUT);
        vm.assume(thawingPeriod <= MAX_THAWING_PERIOD);

        _createProvision(users.indexer, dataService, tokens, maxVerifierCut, thawingPeriod);
    }

    /*
     * HELPERS: these are shortcuts to perform common actions that often involve multiple contract calls
     */
    function _createProvision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        _stakeTo(serviceProvider, tokens);
        _provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
    }

    function _setDelegationFeeCut(IGraphPayments.PaymentTypes paymentType, uint256 cut) internal {
        staking.setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
        uint256 delegationFeeCut = staking.getDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType);
        assertEq(delegationFeeCut, cut);
    }

    /*
     * ACTIONS: these are individual contract calls wrapped in assertion blocks to ensure they work as expected
     */
    function _stake(uint256 tokens) internal {
        (, address msgSender, ) = vm.readCallers();
        _stakeTo(msgSender, tokens);
    }

    function _stakeTo(address serviceProvider, uint256 tokens) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // stakeTo
        token.approve(address(staking), tokens);
        vm.expectEmit();
        emit IHorizonStakingBase.StakeDeposited(serviceProvider, tokens);
        staking.stakeTo(serviceProvider, tokens);

        // after
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // assert
        assertEq(afterStakingBalance, beforeStakingBalance + tokens);
        assertEq(afterSenderBalance, beforeSenderBalance - tokens);
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked + tokens);
        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );
    }

    function _unstake(uint256 _tokens) internal {
        (, address msgSender, ) = vm.readCallers();

        uint256 deprecatedThawingPeriod = uint256(vm.load(address(staking), bytes32(uint256(13))));

        // before
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(msgSender);

        bool withdrawCalled = beforeServiceProvider.__DEPRECATED_tokensLocked != 0 &&
            block.number >= beforeServiceProvider.__DEPRECATED_tokensLockedUntil;

        if (deprecatedThawingPeriod != 0 && beforeServiceProvider.__DEPRECATED_tokensLocked > 0) {
            deprecatedThawingPeriod = MathUtils.weightedAverageRoundingUp(
                MathUtils.diffOrZero(
                    withdrawCalled ? 0 : beforeServiceProvider.__DEPRECATED_tokensLockedUntil,
                    block.number
                ),
                withdrawCalled ? 0 : beforeServiceProvider.__DEPRECATED_tokensLocked,
                deprecatedThawingPeriod,
                _tokens
            );
        }

        // unstake
        if (deprecatedThawingPeriod == 0) {
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.StakeWithdrawn(msgSender, _tokens);
        } else {
            if (withdrawCalled) {
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.StakeWithdrawn(msgSender, beforeServiceProvider.__DEPRECATED_tokensLocked);
            }

            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.StakeLocked(
                msgSender,
                withdrawCalled ? _tokens : beforeServiceProvider.__DEPRECATED_tokensLocked + _tokens,
                block.number + deprecatedThawingPeriod
            );
        }
        staking.unstake(_tokens);

        // after
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(msgSender);

        // assert
        if (deprecatedThawingPeriod == 0) {
            assertEq(afterSenderBalance, _tokens + beforeSenderBalance);
            assertEq(afterStakingBalance, beforeStakingBalance - _tokens);
            assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked - _tokens);
            assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
            assertEq(
                afterServiceProvider.__DEPRECATED_tokensAllocated,
                beforeServiceProvider.__DEPRECATED_tokensAllocated
            );
            assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
            assertEq(
                afterServiceProvider.__DEPRECATED_tokensLockedUntil,
                beforeServiceProvider.__DEPRECATED_tokensLockedUntil
            );
        } else {
            assertEq(
                afterServiceProvider.tokensStaked,
                withdrawCalled
                    ? beforeServiceProvider.tokensStaked - beforeServiceProvider.__DEPRECATED_tokensLocked
                    : beforeServiceProvider.tokensStaked
            );
            assertEq(
                afterServiceProvider.__DEPRECATED_tokensLocked,
                _tokens + (withdrawCalled ? 0 : beforeServiceProvider.__DEPRECATED_tokensLocked)
            );
            assertEq(afterServiceProvider.__DEPRECATED_tokensLockedUntil, block.number + deprecatedThawingPeriod);
            assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
            assertEq(
                afterServiceProvider.__DEPRECATED_tokensAllocated,
                beforeServiceProvider.__DEPRECATED_tokensAllocated
            );
            uint256 tokensTransferred = (withdrawCalled ? beforeServiceProvider.__DEPRECATED_tokensLocked : 0);
            assertEq(afterSenderBalance, beforeSenderBalance + tokensTransferred);
            assertEq(afterStakingBalance, beforeStakingBalance - tokensTransferred);
        }
    }

    function _withdraw() internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(msgSender);
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        // withdraw
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.StakeWithdrawn(msgSender, beforeServiceProvider.__DEPRECATED_tokensLocked);
        staking.withdraw();

        // after
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(msgSender);
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        // assert
        assertEq(afterSenderBalance - beforeSenderBalance, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(beforeStakingBalance - afterStakingBalance, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.tokensStaked,
            beforeServiceProvider.tokensStaked - beforeServiceProvider.__DEPRECATED_tokensLocked
        );
        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, 0);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLockedUntil, 0);
    }

    function _provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        // before
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // provision
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionCreated(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
        staking.provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // assert
        assertEq(afterProvision.tokens, tokens);
        assertEq(afterProvision.tokensThawing, 0);
        assertEq(afterProvision.sharesThawing, 0);
        assertEq(afterProvision.maxVerifierCut, maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, thawingPeriod);
        assertEq(afterProvision.createdAt, uint64(block.timestamp));
        assertEq(afterProvision.maxVerifierCutPending, maxVerifierCut);
        assertEq(afterProvision.thawingPeriodPending, thawingPeriod);
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        assertEq(afterServiceProvider.tokensProvisioned, tokens + beforeServiceProvider.tokensProvisioned);
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );
    }

    function _addToProvision(address serviceProvider, address verifier, uint256 tokens) internal {
        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // addToProvision
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionIncreased(serviceProvider, verifier, tokens);
        staking.addToProvision(serviceProvider, verifier, tokens);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens + tokens);
        assertEq(afterProvision.tokensThawing, beforeProvision.tokensThawing);
        assertEq(afterProvision.sharesThawing, beforeProvision.sharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned + tokens);
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );
    }

    function _thaw(address serviceProvider, address verifier, uint256 tokens) internal returns (bytes32) {
        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );

        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(users.indexer, subgraphDataServiceAddress, users.indexer, beforeThawRequestList.nonce)
        );
        uint256 thawingShares = beforeProvision.sharesThawing == 0
            ? tokens
            : (beforeProvision.sharesThawing * tokens) / beforeProvision.tokensThawing;

        // thaw
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawRequestCreated(
            serviceProvider,
            verifier,
            serviceProvider,
            thawingShares,
            uint64(block.timestamp + beforeProvision.thawingPeriod),
            expectedThawRequestId
        );
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ProvisionThawed(serviceProvider, verifier, tokens);
        bytes32 thawRequestId = staking.thaw(serviceProvider, verifier, tokens);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        ThawRequest memory afterThawRequest = staking.getThawRequest(thawRequestId);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );
        ThawRequest memory afterPreviousTailThawRequest = staking.getThawRequest(beforeThawRequestList.tail);

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens);
        assertEq(afterProvision.tokensThawing, beforeProvision.tokensThawing + tokens);
        assertEq(afterProvision.sharesThawing, beforeProvision.sharesThawing + thawingShares);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);
        assertEq(thawRequestId, expectedThawRequestId);
        assertEq(afterThawRequest.shares, thawingShares);
        assertEq(afterThawRequest.thawingUntil, block.timestamp + beforeProvision.thawingPeriod);
        assertEq(afterThawRequest.next, bytes32(0));
        assertEq(
            afterThawRequestList.head,
            beforeThawRequestList.count == 0 ? thawRequestId : beforeThawRequestList.head
        );
        assertEq(afterThawRequestList.tail, thawRequestId);
        assertEq(afterThawRequestList.count, beforeThawRequestList.count + 1);
        assertEq(afterThawRequestList.nonce, beforeThawRequestList.nonce + 1);
        if (beforeThawRequestList.count != 0) {
            assertEq(afterPreviousTailThawRequest.next, thawRequestId);
        }

        return thawRequestId;
    }

    function _deprovision(address serviceProvider, address verifier, uint256 nThawRequests) internal {
        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );

        (
            uint256 calcTokensThawed,
            uint256 calcTokensThawing,
            uint256 calcSharesThawing,
            ThawRequest[] memory calcThawRequestsFulfilledList,
            bytes32[] memory calcThawRequestsFulfilledListIds,
            uint256[] memory calcThawRequestsFulfilledListTokens
        ) = calcThawRequestData(serviceProvider, verifier, serviceProvider, nThawRequests);

        // deprovision
        for (uint i = 0; i < calcThawRequestsFulfilledList.length; i++) {
            ThawRequest memory thawRequest = calcThawRequestsFulfilledList[i];
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ThawRequestFulfilled(
                calcThawRequestsFulfilledListIds[i],
                calcThawRequestsFulfilledListTokens[i],
                thawRequest.shares,
                thawRequest.thawingUntil
            );
        }
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawRequestsFulfilled(
            serviceProvider,
            verifier,
            serviceProvider,
            calcThawRequestsFulfilledList.length,
            calcTokensThawed
        );
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.TokensDeprovisioned(serviceProvider, verifier, calcTokensThawed);
        staking.deprovision(serviceProvider, verifier, nThawRequests);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens - calcTokensThawed);
        assertEq(afterProvision.tokensThawing, calcTokensThawing);
        assertEq(afterProvision.sharesThawing, calcSharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned - calcTokensThawed);
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );
        for (uint i = 0; i < calcThawRequestsFulfilledListIds.length; i++) {
            ThawRequest memory thawRequest = staking.getThawRequest(calcThawRequestsFulfilledListIds[i]);
            assertEq(thawRequest.shares, 0);
            assertEq(thawRequest.thawingUntil, 0);
            assertEq(thawRequest.next, bytes32(0));
        }
        if (calcThawRequestsFulfilledList.length == 0) {
            assertEq(afterThawRequestList.head, beforeThawRequestList.head);
        } else {
            assertEq(
                afterThawRequestList.head,
                calcThawRequestsFulfilledList.length == beforeThawRequestList.count
                    ? bytes32(0)
                    : calcThawRequestsFulfilledList[calcThawRequestsFulfilledList.length - 1].next
            );
        }
        assertEq(
            afterThawRequestList.tail,
            calcThawRequestsFulfilledList.length == beforeThawRequestList.count
                ? bytes32(0)
                : beforeThawRequestList.tail
        );
        assertEq(afterThawRequestList.count, beforeThawRequestList.count - calcThawRequestsFulfilledList.length);
        assertEq(afterThawRequestList.nonce, beforeThawRequestList.nonce);
    }

    function _reprovision(
        address serviceProvider,
        address verifier,
        address newVerifier,
        uint256 tokens,
        uint256 nThawRequests
    ) internal {
        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        Provision memory beforeProvisionNewVerifier = staking.getProvision(serviceProvider, newVerifier);
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );

        (
            uint256 calcTokensThawed,
            uint256 calcTokensThawing,
            uint256 calcSharesThawing,
            ThawRequest[] memory calcThawRequestsFulfilledList,
            bytes32[] memory calcThawRequestsFulfilledListIds,
            uint256[] memory calcThawRequestsFulfilledListTokens
        ) = calcThawRequestData(serviceProvider, verifier, serviceProvider, nThawRequests);

        // reprovision
        for (uint i = 0; i < calcThawRequestsFulfilledList.length; i++) {
            ThawRequest memory thawRequest = calcThawRequestsFulfilledList[i];
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ThawRequestFulfilled(
                calcThawRequestsFulfilledListIds[i],
                calcThawRequestsFulfilledListTokens[i],
                thawRequest.shares,
                thawRequest.thawingUntil
            );
        }
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawRequestsFulfilled(
            serviceProvider,
            verifier,
            serviceProvider,
            calcThawRequestsFulfilledList.length,
            calcTokensThawed
        );
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.TokensDeprovisioned(serviceProvider, verifier, calcTokensThawed);
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionIncreased(serviceProvider, newVerifier, tokens);
        staking.reprovision(serviceProvider, verifier, newVerifier, tokens, nThawRequests);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        Provision memory afterProvisionNewVerifier = staking.getProvision(serviceProvider, newVerifier);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );

        // assert: provision old verifier
        assertEq(afterProvision.tokens, beforeProvision.tokens - calcTokensThawed);
        assertEq(afterProvision.tokensThawing, calcTokensThawing);
        assertEq(afterProvision.sharesThawing, calcSharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);

        // assert: provision new verifier
        assertEq(afterProvisionNewVerifier.tokens, beforeProvisionNewVerifier.tokens + tokens);
        assertEq(afterProvisionNewVerifier.tokensThawing, beforeProvisionNewVerifier.tokensThawing);
        assertEq(afterProvisionNewVerifier.sharesThawing, beforeProvisionNewVerifier.sharesThawing);
        assertEq(afterProvisionNewVerifier.maxVerifierCut, beforeProvisionNewVerifier.maxVerifierCut);
        assertEq(afterProvisionNewVerifier.thawingPeriod, beforeProvisionNewVerifier.thawingPeriod);
        assertEq(afterProvisionNewVerifier.createdAt, beforeProvisionNewVerifier.createdAt);
        assertEq(afterProvisionNewVerifier.maxVerifierCutPending, beforeProvisionNewVerifier.maxVerifierCutPending);
        assertEq(afterProvisionNewVerifier.thawingPeriodPending, beforeProvisionNewVerifier.thawingPeriodPending);

        // assert: service provider
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        assertEq(
            afterServiceProvider.tokensProvisioned,
            beforeServiceProvider.tokensProvisioned + tokens - calcTokensThawed
        );
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );

        // assert: thaw request list old verifier
        for (uint i = 0; i < calcThawRequestsFulfilledListIds.length; i++) {
            ThawRequest memory thawRequest = staking.getThawRequest(calcThawRequestsFulfilledListIds[i]);
            assertEq(thawRequest.shares, 0);
            assertEq(thawRequest.thawingUntil, 0);
            assertEq(thawRequest.next, bytes32(0));
        }
        if (calcThawRequestsFulfilledList.length == 0) {
            assertEq(afterThawRequestList.head, beforeThawRequestList.head);
        } else {
            assertEq(
                afterThawRequestList.head,
                calcThawRequestsFulfilledList.length == beforeThawRequestList.count
                    ? bytes32(0)
                    : calcThawRequestsFulfilledList[calcThawRequestsFulfilledList.length - 1].next
            );
        }
        assertEq(
            afterThawRequestList.tail,
            calcThawRequestsFulfilledList.length == beforeThawRequestList.count
                ? bytes32(0)
                : beforeThawRequestList.tail
        );
        assertEq(afterThawRequestList.count, beforeThawRequestList.count - calcThawRequestsFulfilledList.length);
        assertEq(afterThawRequestList.nonce, beforeThawRequestList.nonce);
    }

    function _setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);

        // setProvisionParameters
        if (beforeProvision.maxVerifierCut != maxVerifierCut || beforeProvision.thawingPeriod != thawingPeriod) {
            vm.expectEmit();
            emit IHorizonStakingMain.ProvisionParametersStaged(
                serviceProvider,
                verifier,
                maxVerifierCut,
                thawingPeriod
            );
        }
        staking.setProvisionParameters(serviceProvider, verifier, maxVerifierCut, thawingPeriod);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens);
        assertEq(afterProvision.tokensThawing, beforeProvision.tokensThawing);
        assertEq(afterProvision.sharesThawing, beforeProvision.sharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, maxVerifierCut);
        assertEq(afterProvision.thawingPeriodPending, thawingPeriod);
    }

    function _acceptProvisionParameters(address serviceProvider) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, msgSender);

        // acceptProvisionParameters
        if (
            beforeProvision.maxVerifierCutPending != beforeProvision.maxVerifierCut ||
            beforeProvision.thawingPeriodPending != beforeProvision.thawingPeriod
        ) {
            vm.expectEmit();
            emit IHorizonStakingMain.ProvisionParametersSet(
                serviceProvider,
                msgSender,
                beforeProvision.maxVerifierCutPending,
                beforeProvision.thawingPeriodPending
            );
        }
        staking.acceptProvisionParameters(serviceProvider);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, msgSender);

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens);
        assertEq(afterProvision.tokensThawing, beforeProvision.tokensThawing);
        assertEq(afterProvision.sharesThawing, beforeProvision.sharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.maxVerifierCut, afterProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriodPending);
        assertEq(afterProvision.thawingPeriod, afterProvision.thawingPeriodPending);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
    }

    /*
     * STORAGE HELPERS
     */
    function _getStorage_ServiceProviderInternal(
        address serviceProvider
    ) internal view returns (ServiceProviderInternal memory) {
        uint256 slotNumber = 14;
        uint256 baseSlotUint = uint256(keccak256(abi.encode(serviceProvider, slotNumber)));

        ServiceProviderInternal memory serviceProviderInternal = ServiceProviderInternal({
            tokensStaked: uint256(vm.load(address(staking), bytes32(baseSlotUint))),
            __DEPRECATED_tokensAllocated: uint256(vm.load(address(staking), bytes32(baseSlotUint + 1))),
            __DEPRECATED_tokensLocked: uint256(vm.load(address(staking), bytes32(baseSlotUint + 2))),
            __DEPRECATED_tokensLockedUntil: uint256(vm.load(address(staking), bytes32(baseSlotUint + 3))),
            tokensProvisioned: uint256(vm.load(address(staking), bytes32(baseSlotUint + 4)))
        });

        return serviceProviderInternal;
    }

    function _setStorage_DeprecatedThawingPeriod(uint32 _thawingPeriod) internal {
        uint256 slot = 13;
        bytes32 value = bytes32(uint256(_thawingPeriod));
        vm.store(address(staking), bytes32(slot), value);
    }

    function _setStorage_ServiceProvider(
        address _indexer,
        uint256 _tokensStaked,
        uint256 _tokensAllocated,
        uint256 _tokensLocked,
        uint256 _tokensLockedUntil,
        uint256 _tokensProvisioned
    ) internal {
        uint256 serviceProviderSlot = 14;
        bytes32 serviceProviderBaseSlot = keccak256(abi.encode(_indexer, serviceProviderSlot));
        vm.store(address(staking), bytes32(uint256(serviceProviderBaseSlot)), bytes32(_tokensStaked));
        vm.store(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 1), bytes32(_tokensAllocated));
        vm.store(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 2), bytes32(_tokensLocked));
        vm.store(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 3), bytes32(_tokensLockedUntil));
        vm.store(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 4), bytes32(_tokensProvisioned));
    }

    /*
     * MISC: private functions to help with testing
     */
    function calcThawRequestData(
        address serviceProvider,
        address verifier,
        address owner,
        uint256 iterations
    ) private view returns (uint256, uint256, uint256, ThawRequest[] memory, bytes32[] memory, uint256[] memory) {
        LinkedList.List memory thawRequestList = staking.getThawRequestList(serviceProvider, verifier, owner);
        if (thawRequestList.count == 0) {
            return (0, 0, 0, new ThawRequest[](0), new bytes32[](0), new uint256[](0));
        }

        Provision memory prov = staking.getProvision(serviceProvider, verifier);

        uint256 tokensThawed = 0;
        uint256 tokensThawing = prov.tokensThawing;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 thawRequestsFulfilled = 0;

        bytes32 thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0) && (iterations == 0 || thawRequestsFulfilled < iterations)) {
            ThawRequest memory thawRequest = staking.getThawRequest(thawRequestId);
            if (thawRequest.thawingUntil <= block.timestamp) {
                thawRequestsFulfilled++;
                uint256 tokens = (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
                tokensThawed += tokens;
                tokensThawing -= tokens;
                sharesThawing -= thawRequest.shares;
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }

        // we need to do a second pass because solidity doesnt allow dynamic arrays on memory
        ThawRequest[] memory thawRequestsFulfilledList = new ThawRequest[](thawRequestsFulfilled);
        bytes32[] memory thawRequestsFulfilledListIds = new bytes32[](thawRequestsFulfilled);
        uint256[] memory thawRequestsFulfilledListTokens = new uint256[](thawRequestsFulfilled);
        uint256 i = 0;
        thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0) && (iterations == 0 || i < iterations)) {
            ThawRequest memory thawRequest = staking.getThawRequest(thawRequestId);
            if (thawRequest.thawingUntil <= block.timestamp) {
                uint256 tokens = (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
                thawRequestsFulfilledListTokens[i] = tokens;
                thawRequestsFulfilledListIds[i] = thawRequestId;
                thawRequestsFulfilledList[i] = staking.getThawRequest(thawRequestId);
                thawRequestId = thawRequestsFulfilledList[i].next;
                i++;
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }

        assertEq(thawRequestsFulfilled, thawRequestsFulfilledList.length);
        assertEq(thawRequestsFulfilled, thawRequestsFulfilledListIds.length);
        assertEq(thawRequestsFulfilled, thawRequestsFulfilledListTokens.length);

        return (
            tokensThawed,
            tokensThawing,
            sharesThawing,
            thawRequestsFulfilledList,
            thawRequestsFulfilledListIds,
            thawRequestsFulfilledListTokens
        );
    }
}
