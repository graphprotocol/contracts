// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingBase } from "../../../contracts/interfaces/internal/IHorizonStakingBase.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";
import { IL2StakingBase } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingBase.sol";

import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";
import { MathUtils } from "../../../contracts/libraries/MathUtils.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";
import { ExponentialRebates } from "../../../contracts/staking/libraries/ExponentialRebates.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {
    using LinkedList for LinkedList.List;
    using PPMMath for uint256;

    event Transfer(address indexed from, address indexed to, uint tokens);

    address internal _allocationId = makeAddr("allocationId");
    bytes32 internal constant _subgraphDeploymentID = keccak256("subgraphDeploymentID");
    uint256 internal constant MAX_ALLOCATION_EPOCHS = 28;

    uint32 internal alphaNumerator = 100;
    uint32 internal alphaDenominator = 100;
    uint32 internal lambdaNumerator = 60;
    uint32 internal lambdaDenominator = 100;

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
        _setOperator(users.operator, subgraphDataServiceAddress, true);
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
        _setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
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

    modifier useAllocation(uint256 tokens) {
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        _createAllocation(users.indexer, _allocationId, _subgraphDeploymentID, tokens);
        _;
    }

    modifier useRebateParameters() {
        _setStorage_RebateParameters(alphaNumerator, alphaDenominator, lambdaNumerator, lambdaDenominator);
        _;
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

    // This allows setting up contract state with legacy allocations
    function _createAllocation(
        address serviceProvider,
        address allocationId,
        bytes32 subgraphDeploymentID,
        uint256 tokens
    ) internal {
        _setStorage_MaxAllocationEpochs(MAX_ALLOCATION_EPOCHS);

        IHorizonStakingExtension.Allocation memory _allocation = IHorizonStakingExtension.Allocation({
            indexer: serviceProvider,
            subgraphDeploymentID: subgraphDeploymentID,
            tokens: tokens,
            createdAtEpoch: block.timestamp,
            closedAtEpoch: 0,
            collectedFees: 0,
            __DEPRECATED_effectiveAllocation: 0,
            accRewardsPerAllocatedToken: 0,
            distributedRebates: 0
        });
        _setStorage_allocation(_allocation, allocationId, tokens);

        // delegation pool initialized
        _setStorage_DelegationPool(serviceProvider, 0, uint32(PPMMath.MAX_PPM), uint32(PPMMath.MAX_PPM));

        token.transfer(address(staking), tokens);
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

        uint256 deprecatedThawingPeriod = staking.__DEPRECATED_getThawingPeriod();

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
        __provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod, false);
    }

    function _provisionLocked(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        __provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod, true);
    }

    function __provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        bool locked
    ) private {
        // before
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);

        // provision
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionCreated(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
        if (locked) {
            staking.provisionLocked(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
        } else {
            staking.provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
        }

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
            abi.encodePacked(users.indexer, verifier, users.indexer, beforeThawRequestList.nonce)
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
        ) = calcThawRequestData(serviceProvider, verifier, serviceProvider, nThawRequests, false);

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
        ) = calcThawRequestData(serviceProvider, verifier, serviceProvider, nThawRequests, false);

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

    function _setOperator(address operator, address verifier, bool allow) internal {
        __setOperator(operator, verifier, allow, false);
    }

    function _setOperatorLocked(address operator, address verifier, bool allow) internal {
        __setOperator(operator, verifier, allow, true);
    }

    function __setOperator(address operator, address verifier, bool allow, bool locked) private {
        (, address msgSender, ) = vm.readCallers();

        // staking contract knows the address of the legacy subgraph service
        // but we cannot read it as it's an immutable, we have to use the global var :/
        bool legacy = verifier == subgraphDataServiceLegacyAddress;

        // before
        bool beforeOperatorAllowed = _getStorage_OperatorAuth(msgSender, operator, verifier, legacy);
        bool beforeOperatorAllowedGetter = staking.isAuthorized(operator, msgSender, verifier);
        assertEq(beforeOperatorAllowed, beforeOperatorAllowedGetter);

        // setOperator
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.OperatorSet(msgSender, operator, verifier, allow);
        if (locked) {
            staking.setOperatorLocked(operator, verifier, allow);
        } else {
            staking.setOperator(operator, verifier, allow);
        }

        // after
        bool afterOperatorAllowed = _getStorage_OperatorAuth(msgSender, operator, verifier, legacy);
        bool afterOperatorAllowedGetter = staking.isAuthorized(operator, msgSender, verifier);
        assertEq(afterOperatorAllowed, afterOperatorAllowedGetter);

        // assert
        assertEq(afterOperatorAllowed, allow);
    }

    function _delegate(address serviceProvider, address verifier, uint256 tokens, uint256 minSharesOut) internal {
        __delegate(serviceProvider, verifier, tokens, minSharesOut, false);
    }

    function _delegate(address serviceProvider, uint256 tokens) internal {
        __delegate(serviceProvider, subgraphDataServiceLegacyAddress, tokens, 0, true);
    }

    function __delegate(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint256 minSharesOut,
        bool legacy
    ) private {
        (, address delegator, ) = vm.readCallers();

        // before
        DelegationPoolInternalTest memory beforePool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        DelegationInternal memory beforeDelegation = _getStorage_Delegation(
            serviceProvider,
            verifier,
            delegator,
            legacy
        );
        uint256 beforeDelegatorBalance = token.balanceOf(delegator);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        uint256 calcShares = (beforePool.tokens == 0 || beforePool.tokens == beforePool.tokensThawing)
            ? tokens
            : ((tokens * beforePool.shares) / (beforePool.tokens - beforePool.tokensThawing));

        // delegate
        token.approve(address(staking), tokens);
        vm.expectEmit();
        emit IHorizonStakingMain.TokensDelegated(serviceProvider, verifier, delegator, tokens);
        if (legacy) {
            staking.delegate(serviceProvider, tokens);
        } else {
            staking.delegate(serviceProvider, verifier, tokens, minSharesOut);
        }

        // after
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        DelegationInternal memory afterDelegation = _getStorage_Delegation(
            serviceProvider,
            verifier,
            delegator,
            legacy
        );
        uint256 afterDelegatorBalance = token.balanceOf(delegator);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        uint256 deltaShares = afterDelegation.shares - beforeDelegation.shares;

        // assertions
        assertEq(beforePool.tokens + tokens, afterPool.tokens);
        assertEq(beforePool.shares + calcShares, afterPool.shares);
        assertEq(beforePool.tokensThawing, afterPool.tokensThawing);
        assertEq(beforePool.sharesThawing, afterPool.sharesThawing);
        assertEq(beforeDelegation.shares + calcShares, afterDelegation.shares);
        assertEq(beforeDelegation.__DEPRECATED_tokensLocked, afterDelegation.__DEPRECATED_tokensLocked);
        assertEq(beforeDelegation.__DEPRECATED_tokensLockedUntil, afterDelegation.__DEPRECATED_tokensLockedUntil);
        assertGe(deltaShares, minSharesOut);
        assertEq(calcShares, deltaShares);
        assertEq(beforeDelegatorBalance - tokens, afterDelegatorBalance);
        assertEq(beforeStakingBalance + tokens, afterStakingBalance);
    }

    function _undelegate(address serviceProvider, address verifier, uint256 shares) internal {
        __undelegate(serviceProvider, verifier, shares, false);
    }

    function _undelegate(address serviceProvider, uint256 shares) internal {
        __undelegate(serviceProvider, subgraphDataServiceLegacyAddress, shares, true);
    }

    function __undelegate(address serviceProvider, address verifier, uint256 shares, bool legacy) private {
        (, address delegator, ) = vm.readCallers();

        // before
        DelegationPoolInternalTest memory beforePool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        DelegationInternal memory beforeDelegation = _getStorage_Delegation(
            serviceProvider,
            verifier,
            delegator,
            legacy
        );
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(serviceProvider, verifier, delegator);
        uint256 beforeDelegatedTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);

        uint256 calcTokens = ((beforePool.tokens - beforePool.tokensThawing) * shares) / beforePool.shares;
        uint256 calcThawingShares = beforePool.tokensThawing == 0
            ? calcTokens
            : (beforePool.sharesThawing * calcTokens) / beforePool.tokensThawing;
        uint64 calcThawingUntil = staking.getProvision(serviceProvider, verifier).thawingPeriod +
            uint64(block.timestamp);
        bytes32 calcThawRequestId = keccak256(
            abi.encodePacked(serviceProvider, verifier, delegator, beforeThawRequestList.nonce)
        );

        // undelegate
        vm.expectEmit();
        emit IHorizonStakingMain.ThawRequestCreated(
            serviceProvider,
            verifier,
            delegator,
            calcThawingShares,
            calcThawingUntil,
            calcThawRequestId
        );
        vm.expectEmit();
        emit IHorizonStakingMain.TokensUndelegated(serviceProvider, verifier, delegator, calcTokens);
        if (legacy) {
            staking.undelegate(serviceProvider, shares);
        } else {
            staking.undelegate(serviceProvider, verifier, shares);
        }

        // after
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            users.indexer,
            verifier,
            legacy
        );
        DelegationInternal memory afterDelegation = _getStorage_Delegation(
            serviceProvider,
            verifier,
            delegator,
            legacy
        );
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(serviceProvider, verifier, delegator);
        ThawRequest memory afterThawRequest = staking.getThawRequest(calcThawRequestId);
        uint256 afterDelegatedTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);

        // assertions
        assertEq(beforePool.shares, afterPool.shares + shares);
        assertEq(beforePool.tokens, afterPool.tokens);
        assertEq(beforePool.tokensThawing + calcTokens, afterPool.tokensThawing);
        assertEq(beforePool.sharesThawing + calcThawingShares, afterPool.sharesThawing);
        assertEq(beforeDelegation.shares - shares, afterDelegation.shares);
        assertEq(afterThawRequest.shares, calcThawingShares);
        assertEq(afterThawRequest.thawingUntil, calcThawingUntil);
        assertEq(afterThawRequest.next, bytes32(0));
        assertEq(calcThawRequestId, afterThawRequestList.tail);
        assertEq(beforeThawRequestList.nonce + 1, afterThawRequestList.nonce);
        assertEq(beforeThawRequestList.count + 1, afterThawRequestList.count);
        assertEq(afterDelegatedTokens + calcTokens, beforeDelegatedTokens);
    }

    function _withdrawDelegated(
        address serviceProvider,
        address verifier,
        address newServiceProvider,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) internal {
        __withdrawDelegated(
            serviceProvider,
            verifier,
            newServiceProvider,
            minSharesForNewProvider,
            nThawRequests,
            false
        );
    }

    function _withdrawDelegated(address serviceProvider, address newServiceProvider) internal {
        __withdrawDelegated(serviceProvider, subgraphDataServiceLegacyAddress, newServiceProvider, 0, 0, true);
    }

    function __withdrawDelegated(
        address _serviceProvider,
        address _verifier,
        address _newServiceProvider,
        uint256 _minSharesForNewProvider,
        uint256 _nThawRequests,
        bool legacy
    ) private {
        (, address msgSender, ) = vm.readCallers();

        bool reDelegate = _newServiceProvider != address(0);

        // before
        DelegationPoolInternalTest memory beforeDelegationPool = _getStorage_DelegationPoolInternal(
            _serviceProvider,
            _verifier,
            legacy
        );
        DelegationPoolInternalTest memory beforeNewDelegationPool = _getStorage_DelegationPoolInternal(
            _newServiceProvider,
            _verifier,
            legacy
        );
        DelegationInternal memory beforeNewDelegation = _getStorage_Delegation(
            _newServiceProvider,
            _verifier,
            msgSender,
            legacy
        );
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(
            _serviceProvider,
            _verifier,
            msgSender
        );
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        (
            uint256 calcTokensThawed,
            uint256 calcTokensThawing,
            uint256 calcSharesThawing,
            ThawRequest[] memory calcThawRequestsFulfilledList,
            bytes32[] memory calcThawRequestsFulfilledListIds,
            uint256[] memory calcThawRequestsFulfilledListTokens
        ) = calcThawRequestData(_serviceProvider, _verifier, msgSender, _nThawRequests, true);

        // withdrawDelegated
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
            _serviceProvider,
            _verifier,
            msgSender,
            calcThawRequestsFulfilledList.length,
            calcTokensThawed
        );
        if (calcTokensThawed != 0) {
            vm.expectEmit();
            if (reDelegate) {
                emit IHorizonStakingMain.TokensDelegated(_newServiceProvider, _verifier, msgSender, calcTokensThawed);
            } else {
                emit Transfer(address(staking), msgSender, calcTokensThawed);
            }
        }
        vm.expectEmit();
        emit IHorizonStakingMain.DelegatedTokensWithdrawn(_serviceProvider, _verifier, msgSender, calcTokensThawed);
        staking.withdrawDelegated(
            _serviceProvider,
            _verifier,
            _newServiceProvider,
            _minSharesForNewProvider,
            _nThawRequests
        );

        // after
        DelegationPoolInternalTest memory afterDelegationPool = _getStorage_DelegationPoolInternal(
            _serviceProvider,
            _verifier,
            legacy
        );
        DelegationPoolInternalTest memory afterNewDelegationPool = _getStorage_DelegationPoolInternal(
            _newServiceProvider,
            _verifier,
            legacy
        );
        DelegationInternal memory afterNewDelegation = _getStorage_Delegation(
            _newServiceProvider,
            _verifier,
            msgSender,
            legacy
        );
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            _serviceProvider,
            _verifier,
            msgSender
        );
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        // assert
        assertEq(afterDelegationPool.tokens, beforeDelegationPool.tokens - calcTokensThawed);
        assertEq(afterDelegationPool.shares, beforeDelegationPool.shares);
        assertEq(afterDelegationPool.tokensThawing, calcTokensThawing);
        assertEq(afterDelegationPool.sharesThawing, calcSharesThawing);

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

        if (reDelegate) {
            uint256 calcShares = (afterNewDelegationPool.tokens == 0 ||
                afterNewDelegationPool.tokens == afterNewDelegationPool.tokensThawing)
                ? calcTokensThawed
                : ((calcTokensThawed * afterNewDelegationPool.shares) /
                    (afterNewDelegationPool.tokens - afterNewDelegationPool.tokensThawing));
            uint256 deltaShares = afterNewDelegation.shares - beforeNewDelegation.shares;

            assertEq(afterNewDelegationPool.tokens, beforeNewDelegationPool.tokens + calcTokensThawed);
            assertEq(afterNewDelegationPool.shares, beforeNewDelegationPool.shares + calcShares);
            assertEq(afterNewDelegationPool.tokensThawing, beforeNewDelegationPool.tokensThawing);
            assertEq(afterNewDelegationPool.sharesThawing, beforeNewDelegationPool.sharesThawing);
            assertEq(afterNewDelegation.shares, beforeNewDelegation.shares + calcShares);
            assertEq(afterNewDelegation.__DEPRECATED_tokensLocked, beforeNewDelegation.__DEPRECATED_tokensLocked);
            assertEq(
                afterNewDelegation.__DEPRECATED_tokensLockedUntil,
                beforeNewDelegation.__DEPRECATED_tokensLockedUntil
            );
            assertGe(deltaShares, _minSharesForNewProvider);
            assertEq(calcShares, deltaShares);
            assertEq(afterSenderBalance - beforeSenderBalance, 0);
            assertEq(beforeStakingBalance - afterStakingBalance, 0);
        } else {
            assertEq(beforeStakingBalance - afterStakingBalance, calcTokensThawed);
            assertEq(afterSenderBalance - beforeSenderBalance, calcTokensThawed);
        }
    }

    function _addToDelegationPool(address serviceProvider, address verifier, uint256 tokens) internal {
        (, address msgSender, ) = vm.readCallers();

        // staking contract knows the address of the legacy subgraph service
        // but we cannot read it as it's an immutable, we have to use the global var :/
        bool legacy = verifier == subgraphDataServiceLegacyAddress;

        // before
        DelegationPoolInternalTest memory beforePool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        // addToDelegationPool
        vm.expectEmit();
        emit Transfer(msgSender, address(staking), tokens);
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.TokensToDelegationPoolAdded(serviceProvider, verifier, tokens);
        staking.addToDelegationPool(serviceProvider, verifier, tokens);

        // after
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        // assert
        assertEq(beforeSenderBalance - tokens, afterSenderBalance);
        assertEq(beforeStakingBalance + tokens, afterStakingBalance);
        assertEq(beforePool.tokens + tokens, afterPool.tokens);
        assertEq(beforePool.shares, afterPool.shares);
        assertEq(beforePool.tokensThawing, afterPool.tokensThawing);
        assertEq(beforePool.sharesThawing, afterPool.sharesThawing);
    }

    function _setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType,
        uint256 feeCut
    ) internal {
        // setDelegationFeeCut
        vm.expectEmit();
        emit IHorizonStakingMain.DelegationFeeCutSet(serviceProvider, verifier, paymentType, feeCut);
        staking.setDelegationFeeCut(serviceProvider, verifier, paymentType, feeCut);

        // after
        uint256 afterDelegationFeeCut = staking.getDelegationFeeCut(serviceProvider, verifier, paymentType);

        // assert
        assertEq(afterDelegationFeeCut, feeCut);
    }

    function _setAllowedLockedVerifier(address verifier, bool allowed) internal {
        // setAllowedLockedVerifier
        vm.expectEmit();
        emit IHorizonStakingMain.AllowedLockedVerifierSet(verifier, allowed);
        staking.setAllowedLockedVerifier(verifier, allowed);

        // after
        bool afterAllowed = staking.isAllowedLockedVerifier(verifier);

        // assert
        assertEq(afterAllowed, allowed);
    }

    function _setDelegationSlashingEnabled() internal {
        // setDelegationSlashingEnabled
        vm.expectEmit();
        emit IHorizonStakingMain.DelegationSlashingEnabled(true);
        staking.setDelegationSlashingEnabled();

        // after
        bool afterEnabled = staking.isDelegationSlashingEnabled();

        // assert
        assertEq(afterEnabled, true);
    }

    function _clearThawingPeriod() internal {
        // clearThawingPeriod
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawingPeriodCleared();
        staking.clearThawingPeriod();

        // after
        uint64 afterThawingPeriod = staking.__DEPRECATED_getThawingPeriod();

        // assert
        assertEq(afterThawingPeriod, 0);
    }

    function _setMaxThawingPeriod(uint64 maxThawingPeriod) internal {
        // setMaxThawingPeriod
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.MaxThawingPeriodSet(maxThawingPeriod);
        staking.setMaxThawingPeriod(maxThawingPeriod);

        // after
        uint64 afterMaxThawingPeriod = staking.getMaxThawingPeriod();

        // assert
        assertEq(afterMaxThawingPeriod, maxThawingPeriod);
    }

    function _setCounterpartStakingAddress(address counterpartStakingAddress) internal {
        // setCounterpartStakingAddress
        vm.expectEmit(address(staking));
        emit IHorizonStakingExtension.CounterpartStakingAddressSet(counterpartStakingAddress);
        staking.setCounterpartStakingAddress(counterpartStakingAddress);

        // after
        address afterCounterpartStakingAddress = _getStorage_CounterpartStakingAddress();

        // assert
        assertEq(afterCounterpartStakingAddress, counterpartStakingAddress);
    }

    function _onTokenTransfer_ReceiveDelegation(address from, uint256 tokens, bytes memory data) internal {
        (, bytes memory fnData) = abi.decode(data, (uint8, bytes));
        (address serviceProvider, address delegator) = abi.decode(fnData, (address, address));
        bytes32 slotPoolTokens = bytes32(uint256(keccak256(abi.encode(serviceProvider, 20))) + 2);

        // before
        DelegationPool memory beforePool = staking.getDelegationPool(serviceProvider, subgraphDataServiceLegacyAddress);
        Delegation memory beforeDelegation = staking.getDelegation(
            serviceProvider,
            subgraphDataServiceLegacyAddress,
            delegator
        );
        uint256 beforeStoragePoolTokens = uint256(vm.load(address(staking), slotPoolTokens));
        uint256 beforeDelegatedTokens = staking.getDelegatedTokensAvailable(
            serviceProvider,
            subgraphDataServiceLegacyAddress
        );
        uint256 beforeDelegatorBalance = token.balanceOf(delegator);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 calcShares = (beforePool.tokens == 0 || beforePool.tokens == beforePool.tokensThawing)
            ? tokens
            : ((tokens * beforePool.shares) / (beforePool.tokens - beforePool.tokensThawing));

        bool earlyExit = (calcShares == 0 || tokens < 1 ether) ||
            (beforePool.tokens == 0 && (beforePool.shares != 0 || beforePool.sharesThawing != 0));

        // onTokenTransfer
        if (earlyExit) {
            vm.expectEmit();
            emit Transfer(address(staking), delegator, tokens);
            vm.expectEmit();
            emit IL2StakingBase.TransferredDelegationReturnedToDelegator(serviceProvider, delegator, tokens);
        } else {
            vm.expectEmit();
            emit IHorizonStakingExtension.StakeDelegated(serviceProvider, delegator, tokens, calcShares);
        }
        staking.onTokenTransfer(from, tokens, data);

        // after
        DelegationPool memory afterPool = staking.getDelegationPool(serviceProvider, subgraphDataServiceLegacyAddress);
        Delegation memory afterDelegation = staking.getDelegation(
            serviceProvider,
            subgraphDataServiceLegacyAddress,
            delegator
        );
        uint256 afterStoragePoolTokens = uint256(vm.load(address(staking), slotPoolTokens));
        uint256 afterDelegatedTokens = staking.getDelegatedTokensAvailable(
            serviceProvider,
            subgraphDataServiceLegacyAddress
        );
        uint256 afterDelegatorBalance = token.balanceOf(delegator);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        uint256 deltaShares = afterDelegation.shares - beforeDelegation.shares;

        // assertions
        if (earlyExit) {
            assertEq(beforePool.tokens, afterPool.tokens);
            assertEq(beforePool.shares, afterPool.shares);
            assertEq(beforePool.tokensThawing, afterPool.tokensThawing);
            assertEq(beforePool.sharesThawing, afterPool.sharesThawing);
            assertEq(0, deltaShares);
            assertEq(beforeDelegatedTokens, afterDelegatedTokens);
            assertEq(beforeStoragePoolTokens, afterStoragePoolTokens);
            assertEq(beforeDelegatorBalance + tokens, afterDelegatorBalance);
            assertEq(beforeStakingBalance - tokens, afterStakingBalance);
        } else {
            assertEq(beforePool.tokens + tokens, afterPool.tokens);
            assertEq(beforePool.shares + calcShares, afterPool.shares);
            assertEq(beforePool.tokensThawing, afterPool.tokensThawing);
            assertEq(beforePool.sharesThawing, afterPool.sharesThawing);
            assertEq(calcShares, deltaShares);
            assertEq(beforeDelegatedTokens + tokens, afterDelegatedTokens);
            // Ensure correct slot is being updated, pools are stored in different storage locations for legacy subgraph data service
            assertEq(beforeStoragePoolTokens + tokens, afterStoragePoolTokens);
            assertEq(beforeDelegatorBalance, afterDelegatorBalance);
            assertEq(beforeStakingBalance, afterStakingBalance);
        }
    }

    function _slash(address serviceProvider, address verifier, uint256 tokens, uint256 verifierCutAmount) internal {
        bool isDelegationSlashingEnabled = staking.isDelegationSlashingEnabled();

        // staking contract knows the address of the legacy subgraph service
        // but we cannot read it as it's an immutable, we have to use the global var :/
        bool legacy = verifier == subgraphDataServiceLegacyAddress;

        // before
        Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        DelegationPoolInternalTest memory beforePool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeVerifierBalance = token.balanceOf(verifier);

        // Calculate expected tokens after slashing
        uint256 tokensToSlash = MathUtils.min(tokens, beforeProvision.tokens + beforePool.tokens);
        uint256 providerTokensSlashed = MathUtils.min(beforeProvision.tokens, tokensToSlash);
        uint256 delegationTokensSlashed = tokensToSlash - providerTokensSlashed;

        if (tokensToSlash > 0) {
            if (verifierCutAmount > 0) {
                vm.expectEmit(address(token));
                emit Transfer(address(staking), verifier, verifierCutAmount);
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.VerifierTokensSent(serviceProvider, verifier, verifier, verifierCutAmount);
            }
            if (providerTokensSlashed - verifierCutAmount > 0) {
                vm.expectEmit(address(token));
                emit Transfer(address(staking), address(0), providerTokensSlashed - verifierCutAmount);
            }
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ProvisionSlashed(serviceProvider, verifier, providerTokensSlashed);
        }

        if (delegationTokensSlashed > 0) {
            if (isDelegationSlashingEnabled) {
                vm.expectEmit(address(token));
                emit Transfer(address(staking), address(0), delegationTokensSlashed);
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.DelegationSlashed(serviceProvider, verifier, delegationTokensSlashed);
            } else {
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.DelegationSlashingSkipped(serviceProvider, verifier, delegationTokensSlashed);
            }
        }
        staking.slash(serviceProvider, tokens, verifierCutAmount, verifier);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            serviceProvider,
            verifier,
            legacy
        );
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterVerifierBalance = token.balanceOf(verifier);

        uint256 tokensSlashed = providerTokensSlashed + (isDelegationSlashingEnabled ? delegationTokensSlashed : 0);
        uint256 provisionThawingTokens = (beforeProvision.tokensThawing *
            (1e18 - ((providerTokensSlashed * 1e18) / beforeProvision.tokens))) / (1e18);

        // assert
        assertEq(afterProvision.tokens + providerTokensSlashed, beforeProvision.tokens);
        assertEq(afterProvision.tokensThawing, provisionThawingTokens);
        assertEq(afterProvision.sharesThawing, beforeProvision.sharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);

        if (isDelegationSlashingEnabled) {
            uint256 poolThawingTokens = (beforePool.tokensThawing *
                (1e18 - ((delegationTokensSlashed * 1e18) / beforePool.tokens))) / (1e18);
            assertEq(afterPool.tokens + delegationTokensSlashed, beforePool.tokens);
            assertEq(afterPool.shares, beforePool.shares);
            assertEq(afterPool.tokensThawing, poolThawingTokens);
            assertEq(afterPool.sharesThawing, beforePool.sharesThawing);
        }

        assertEq(beforeStakingBalance - tokensSlashed, afterStakingBalance);
        assertEq(beforeVerifierBalance + verifierCutAmount, afterVerifierBalance);

        assertEq(afterServiceProvider.tokensStaked + providerTokensSlashed, beforeServiceProvider.tokensStaked);
        assertEq(
            afterServiceProvider.tokensProvisioned + providerTokensSlashed,
            beforeServiceProvider.tokensProvisioned
        );
    }

    // Current rewards manager is mocked and assumed to mint fixed rewards
    function _closeAllocation(address allocationId, bytes32 poi) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        IHorizonStakingExtension.Allocation memory beforeAllocation = staking.getAllocation(allocationId);
        DelegationPoolInternalTest memory beforePool = _getStorage_DelegationPoolInternal(
            beforeAllocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            beforeAllocation.indexer
        );
        uint256 beforeSubgraphAllocations = _getStorage_SubgraphAllocations(beforeAllocation.subgraphDeploymentID);

        bool isAuth = staking.isAuthorized(msgSender, beforeAllocation.indexer, subgraphDataServiceLegacyAddress);
        address rewardsDestination = _getStorage_RewardsDestination(beforeAllocation.indexer);

        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeIndexerBalance = token.balanceOf(beforeAllocation.indexer);
        uint256 beforeBeneficiaryBalance = token.balanceOf(rewardsDestination);

        uint256 calcRewards = ALLOCATIONS_REWARD_CUT;
        uint256 calcDelegatorRewards = ALLOCATIONS_REWARD_CUT -
            uint256(beforePool.__DEPRECATED_indexingRewardCut).mulPPM(calcRewards);
        uint256 calcIndexerRewards = ALLOCATIONS_REWARD_CUT - (beforePool.tokens > 0 ? calcDelegatorRewards : 0);

        // closeAllocation
        vm.expectEmit(address(staking));
        emit IHorizonStakingExtension.AllocationClosed(
            beforeAllocation.indexer,
            beforeAllocation.subgraphDeploymentID,
            epochManager.currentEpoch(),
            beforeAllocation.tokens,
            allocationId,
            msgSender,
            poi,
            !isAuth
        );
        staking.closeAllocation(allocationId, poi);

        // after
        IHorizonStakingExtension.Allocation memory afterAllocation = staking.getAllocation(allocationId);
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            beforeAllocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            beforeAllocation.indexer
        );
        uint256 afterSubgraphAllocations = _getStorage_SubgraphAllocations(beforeAllocation.subgraphDeploymentID);
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterIndexerBalance = token.balanceOf(beforeAllocation.indexer);
        uint256 afterBeneficiaryBalance = token.balanceOf(rewardsDestination);

        if (beforeAllocation.tokens > 0) {
            if (isAuth && poi != 0) {
                if (rewardsDestination != address(0)) {
                    assertEq(beforeStakingBalance + calcRewards - calcIndexerRewards, afterStakingBalance);
                    assertEq(beforeIndexerBalance, afterIndexerBalance);
                    assertEq(beforeBeneficiaryBalance + calcIndexerRewards, afterBeneficiaryBalance);
                } else {
                    assertEq(beforeStakingBalance + calcRewards, afterStakingBalance);
                    assertEq(beforeIndexerBalance, afterIndexerBalance);
                    assertEq(beforeBeneficiaryBalance, afterBeneficiaryBalance);
                }
            } else {
                assertEq(beforeStakingBalance, afterStakingBalance);
                assertEq(beforeIndexerBalance, afterIndexerBalance);
                assertEq(beforeBeneficiaryBalance, afterBeneficiaryBalance);
            }
        } else {
            assertEq(beforeStakingBalance, afterStakingBalance);
            assertEq(beforeIndexerBalance, afterIndexerBalance);
            assertEq(beforeBeneficiaryBalance, afterBeneficiaryBalance);
        }

        assertEq(afterAllocation.indexer, beforeAllocation.indexer);
        assertEq(afterAllocation.subgraphDeploymentID, beforeAllocation.subgraphDeploymentID);
        assertEq(afterAllocation.tokens, beforeAllocation.tokens);
        assertEq(afterAllocation.createdAtEpoch, beforeAllocation.createdAtEpoch);
        assertEq(afterAllocation.closedAtEpoch, epochManager.currentEpoch());
        assertEq(afterAllocation.collectedFees, beforeAllocation.collectedFees);
        assertEq(afterAllocation.__DEPRECATED_effectiveAllocation, beforeAllocation.__DEPRECATED_effectiveAllocation);
        assertEq(afterAllocation.accRewardsPerAllocatedToken, beforeAllocation.accRewardsPerAllocatedToken);
        assertEq(afterAllocation.distributedRebates, beforeAllocation.distributedRebates);

        if (beforeAllocation.tokens > 0 && isAuth && poi != 0 && rewardsDestination == address(0)) {
            assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked + calcIndexerRewards);
        } else {
            assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        }
        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensAllocated + beforeAllocation.tokens,
            beforeServiceProvider.__DEPRECATED_tokensAllocated
        );
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );

        assertEq(afterSubgraphAllocations + beforeAllocation.tokens, beforeSubgraphAllocations);

        if (beforeAllocation.tokens > 0 && isAuth && poi != 0 && beforePool.tokens > 0) {
            assertEq(afterPool.tokens, beforePool.tokens + calcDelegatorRewards);
        } else {
            assertEq(afterPool.tokens, beforePool.tokens);
        }
    }

    function _collect(uint256 tokens, address allocationId) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        IHorizonStakingExtension.Allocation memory beforeAllocation = staking.getAllocation(allocationId);
        DelegationPoolInternalTest memory beforePool = _getStorage_DelegationPoolInternal(
            beforeAllocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            beforeAllocation.indexer
        );

        (uint32 curationPercentage, uint32 protocolPercentage) = _getStorage_ProtocolTaxAndCuration();
        address rewardsDestination = _getStorage_RewardsDestination(beforeAllocation.indexer);

        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeCurationBalance = token.balanceOf(address(curation));
        uint256 beforeBeneficiaryBalance = token.balanceOf(rewardsDestination);

        // calc some stuff
        uint256 calcProtocolTaxTokens = tokens.mulPPMRoundUp(protocolPercentage);
        uint256 calcQueryFees = tokens - calcProtocolTaxTokens;

        uint256 calcCurationCutTokens = 0;
        if (curation.isCurated(beforeAllocation.subgraphDeploymentID)) {
            calcCurationCutTokens = calcQueryFees.mulPPMRoundUp(curationPercentage);
            calcQueryFees -= calcCurationCutTokens;
        }

        uint256 calcNewRebates = ExponentialRebates.exponentialRebates(
            calcQueryFees + beforeAllocation.collectedFees,
            beforeAllocation.tokens,
            alphaNumerator,
            alphaDenominator,
            lambdaNumerator,
            lambdaDenominator
        );
        uint256 calcPayment = calcNewRebates > calcQueryFees ? calcQueryFees : calcNewRebates;

        uint256 calcDelegationFeeCut = 0;
        if (beforePool.tokens > 0) {
            calcDelegationFeeCut = calcPayment - calcPayment.mulPPM(beforePool.__DEPRECATED_queryFeeCut);
            calcPayment -= calcDelegationFeeCut;
        }

        // staking.collect()
        if (tokens > 0) {
            vm.expectEmit(address(staking));
            emit IHorizonStakingExtension.RebateCollected(
                msgSender,
                beforeAllocation.indexer,
                beforeAllocation.subgraphDeploymentID,
                allocationId,
                epochManager.currentEpoch(),
                tokens,
                calcProtocolTaxTokens,
                calcCurationCutTokens,
                calcQueryFees,
                calcPayment,
                calcDelegationFeeCut
            );
        }
        staking.collect(tokens, allocationId);

        // after
        IHorizonStakingExtension.Allocation memory afterAllocation = staking.getAllocation(allocationId);
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            beforeAllocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            beforeAllocation.indexer
        );

        uint256 afterBeneficiaryBalance = token.balanceOf(rewardsDestination);
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        uint256 afterCurationBalance = token.balanceOf(address(curation));

        // assert

        assertEq(afterSenderBalance + tokens, beforeSenderBalance);
        assertEq(afterCurationBalance, beforeCurationBalance + calcCurationCutTokens);
        if (rewardsDestination != address(0)) {
            assertEq(afterBeneficiaryBalance, beforeBeneficiaryBalance + calcPayment);
            assertEq(afterStakingBalance, beforeStakingBalance + calcDelegationFeeCut);
        } else {
            assertEq(afterBeneficiaryBalance, beforeBeneficiaryBalance);
            assertEq(afterStakingBalance, beforeStakingBalance + calcDelegationFeeCut + calcPayment);
        }

        assertEq(
            afterAllocation.collectedFees,
            beforeAllocation.collectedFees + tokens - calcProtocolTaxTokens - calcCurationCutTokens
        );
        assertEq(afterAllocation.indexer, beforeAllocation.indexer);
        assertEq(afterAllocation.subgraphDeploymentID, beforeAllocation.subgraphDeploymentID);
        assertEq(afterAllocation.tokens, beforeAllocation.tokens);
        assertEq(afterAllocation.createdAtEpoch, beforeAllocation.createdAtEpoch);
        assertEq(afterAllocation.closedAtEpoch, beforeAllocation.closedAtEpoch);
        assertEq(afterAllocation.accRewardsPerAllocatedToken, beforeAllocation.accRewardsPerAllocatedToken);
        assertEq(afterAllocation.distributedRebates, beforeAllocation.distributedRebates + calcNewRebates);

        assertEq(afterPool.tokens, beforePool.tokens + calcDelegationFeeCut);
        assertEq(afterPool.shares, beforePool.shares);
        assertEq(afterPool.tokensThawing, beforePool.tokensThawing);
        assertEq(afterPool.sharesThawing, beforePool.sharesThawing);

        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
        if (rewardsDestination != address(0)) {
            assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        } else {
            assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked + calcPayment);
        }
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

    function _getStorage_OperatorAuth(
        address serviceProvider,
        address operator,
        address verifier,
        bool legacy
    ) internal view returns (bool) {
        uint256 slotNumber = legacy ? 21 : 31;
        uint256 slot;

        if (legacy) {
            slot = uint256(keccak256(abi.encode(operator, keccak256(abi.encode(serviceProvider, slotNumber)))));
        } else {
            slot = uint256(
                keccak256(
                    abi.encode(
                        operator,
                        keccak256(abi.encode(verifier, keccak256(abi.encode(serviceProvider, slotNumber))))
                    )
                )
            );
        }
        return vm.load(address(staking), bytes32(slot)) == bytes32(uint256(1));
    }

    function _setStorage_DeprecatedThawingPeriod(uint32 _thawingPeriod) internal {
        uint256 slot = 13;

        // Read the current value of the slot
        uint256 currentSlotValue = uint256(vm.load(address(staking), bytes32(slot)));

        // Create a mask to clear the bits for __DEPRECATED_thawingPeriod (bits 0-31)
        uint256 mask = ~(uint256(0xFFFFFFFF)); // Mask to clear the first 32 bits

        // Clear the bits for __DEPRECATED_thawingPeriod and set the new value
        uint256 newSlotValue = (currentSlotValue & mask) | uint256(_thawingPeriod);

        // Store the updated value back into the slot
        vm.store(address(staking), bytes32(slot), bytes32(newSlotValue));
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

    // DelegationPoolInternal contains a mapping, solidity doesn't allow constructing structs with
    // nested mappings on memory: "Struct containing a (nested) mapping cannot be constructed"
    // So we use a custom struct here and remove the nested mapping which we don't need anyways
    struct DelegationPoolInternalTest {
        // (Deprecated) Time, in blocks, an indexer must wait before updating delegation parameters
        uint32 __DEPRECATED_cooldownBlocks;
        // (Deprecated) Percentage of indexing rewards for the service provider, in PPM
        uint32 __DEPRECATED_indexingRewardCut;
        // (Deprecated) Percentage of query fees for the service provider, in PPM
        uint32 __DEPRECATED_queryFeeCut;
        // (Deprecated) Block when the delegation parameters were last updated
        uint256 __DEPRECATED_updatedAtBlock;
        // Total tokens as pool reserves
        uint256 tokens;
        // Total shares minted in the pool
        uint256 shares;
        // Delegation details by delegator
        uint256 _gap_delegators_mapping;
        // Tokens thawing in the pool
        uint256 tokensThawing;
        // Shares representing the thawing tokens
        uint256 sharesThawing;
    }

    function _getStorage_DelegationPoolInternal(
        address serviceProvider,
        address verifier,
        bool legacy
    ) internal view returns (DelegationPoolInternalTest memory) {
        uint256 slotNumber = legacy ? 20 : 33;
        uint256 baseSlot;
        if (legacy) {
            baseSlot = uint256(keccak256(abi.encode(serviceProvider, slotNumber)));
        } else {
            baseSlot = uint256(keccak256(abi.encode(verifier, keccak256(abi.encode(serviceProvider, slotNumber)))));
        }

        uint256 packedData = uint256(vm.load(address(staking), bytes32(baseSlot)));

        DelegationPoolInternalTest memory delegationPoolInternal = DelegationPoolInternalTest({
            __DEPRECATED_cooldownBlocks: uint32(packedData & 0xFFFFFFFF),
            __DEPRECATED_indexingRewardCut: uint32((packedData >> 32) & 0xFFFFFFFF),
            __DEPRECATED_queryFeeCut: uint32((packedData >> 64) & 0xFFFFFFFF),
            __DEPRECATED_updatedAtBlock: uint256(vm.load(address(staking), bytes32(baseSlot + 1))),
            tokens: uint256(vm.load(address(staking), bytes32(baseSlot + 2))),
            shares: uint256(vm.load(address(staking), bytes32(baseSlot + 3))),
            _gap_delegators_mapping: uint256(vm.load(address(staking), bytes32(baseSlot + 4))),
            tokensThawing: uint256(vm.load(address(staking), bytes32(baseSlot + 5))),
            sharesThawing: uint256(vm.load(address(staking), bytes32(baseSlot + 6)))
        });

        return delegationPoolInternal;
    }

    function _getStorage_Delegation(
        address serviceProvider,
        address verifier,
        address delegator,
        bool legacy
    ) internal view returns (DelegationInternal memory) {
        uint256 slotNumber = legacy ? 20 : 33;
        uint256 baseSlot;

        // DelegationPool
        if (legacy) {
            baseSlot = uint256(keccak256(abi.encode(serviceProvider, slotNumber)));
        } else {
            baseSlot = uint256(keccak256(abi.encode(verifier, keccak256(abi.encode(serviceProvider, slotNumber)))));
        }

        // delegators slot in DelegationPool
        baseSlot += 4;

        // Delegation
        baseSlot = uint256(keccak256(abi.encode(delegator, baseSlot)));

        DelegationInternal memory delegation = DelegationInternal({
            shares: uint256(vm.load(address(staking), bytes32(baseSlot))),
            __DEPRECATED_tokensLocked: uint256(vm.load(address(staking), bytes32(baseSlot + 1))),
            __DEPRECATED_tokensLockedUntil: uint256(vm.load(address(staking), bytes32(baseSlot + 2)))
        });

        return delegation;
    }

    function _getStorage_CounterpartStakingAddress() internal view returns (address) {
        uint256 slot = 24;
        return address(uint160(uint256(vm.load(address(staking), bytes32(slot)))));
    }

    function _setStorage_allocation(
        IHorizonStakingExtension.Allocation memory allocation,
        address allocationId,
        uint256 tokens
    ) internal {
        // __DEPRECATED_allocations
        uint256 allocationsSlot = 15;
        bytes32 allocationBaseSlot = keccak256(abi.encode(allocationId, allocationsSlot));
        vm.store(address(staking), allocationBaseSlot, bytes32(uint256(uint160(allocation.indexer))));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 1), allocation.subgraphDeploymentID);
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 2), bytes32(tokens));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 3), bytes32(allocation.createdAtEpoch));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 4), bytes32(allocation.closedAtEpoch));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 5), bytes32(allocation.collectedFees));
        vm.store(
            address(staking),
            bytes32(uint256(allocationBaseSlot) + 6),
            bytes32(allocation.__DEPRECATED_effectiveAllocation)
        );
        vm.store(
            address(staking),
            bytes32(uint256(allocationBaseSlot) + 7),
            bytes32(allocation.accRewardsPerAllocatedToken)
        );
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 8), bytes32(allocation.distributedRebates));

        // _serviceProviders
        uint256 serviceProviderSlot = 14;
        bytes32 serviceProviderBaseSlot = keccak256(abi.encode(allocation.indexer, serviceProviderSlot));
        uint256 currentTokensStaked = uint256(vm.load(address(staking), serviceProviderBaseSlot));
        uint256 currentTokensProvisioned = uint256(
            vm.load(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 1))
        );
        vm.store(
            address(staking),
            bytes32(uint256(serviceProviderBaseSlot) + 0),
            bytes32(currentTokensStaked + tokens)
        );
        vm.store(
            address(staking),
            bytes32(uint256(serviceProviderBaseSlot) + 1),
            bytes32(currentTokensProvisioned + tokens)
        );

        // __DEPRECATED_subgraphAllocations
        uint256 subgraphsAllocationsSlot = 16;
        bytes32 subgraphAllocationsBaseSlot = keccak256(
            abi.encode(allocation.subgraphDeploymentID, subgraphsAllocationsSlot)
        );
        uint256 currentAllocatedTokens = uint256(vm.load(address(staking), subgraphAllocationsBaseSlot));
        vm.store(address(staking), subgraphAllocationsBaseSlot, bytes32(currentAllocatedTokens + tokens));
    }

    function _getStorage_SubgraphAllocations(bytes32 subgraphDeploymentID) internal view returns (uint256) {
        uint256 subgraphsAllocationsSlot = 16;
        bytes32 subgraphAllocationsBaseSlot = keccak256(abi.encode(subgraphDeploymentID, subgraphsAllocationsSlot));
        return uint256(vm.load(address(staking), subgraphAllocationsBaseSlot));
    }

    function _setStorage_RewardsDestination(address serviceProvider, address destination) internal {
        uint256 rewardsDestinationSlot = 23;
        bytes32 rewardsDestinationSlotBaseSlot = keccak256(abi.encode(serviceProvider, rewardsDestinationSlot));
        vm.store(address(staking), rewardsDestinationSlotBaseSlot, bytes32(uint256(uint160(destination))));
    }

    function _getStorage_RewardsDestination(address serviceProvider) internal view returns (address) {
        uint256 rewardsDestinationSlot = 23;
        bytes32 rewardsDestinationSlotBaseSlot = keccak256(abi.encode(serviceProvider, rewardsDestinationSlot));
        return address(uint160(uint256(vm.load(address(staking), rewardsDestinationSlotBaseSlot))));
    }

    function _setStorage_MaxAllocationEpochs(uint256 maxAllocationEpochs) internal {
        uint256 slot = 13;

        // Read the current value of the storage slot
        uint256 currentSlotValue = uint256(vm.load(address(staking), bytes32(slot)));

        // Mask to clear the specific bits for __DEPRECATED_maxAllocationEpochs (bits 128-159)
        uint256 mask = ~(uint256(0xFFFFFFFF) << 128);

        // Clear the bits and set the new maxAllocationEpochs value
        uint256 newSlotValue = (currentSlotValue & mask) | (uint256(maxAllocationEpochs) << 128);

        // Store the updated value back into the slot
        vm.store(address(staking), bytes32(slot), bytes32(newSlotValue));

        uint256 readMaxAllocationEpochs = _getStorage_MaxAllocationEpochs();
        assertEq(readMaxAllocationEpochs, maxAllocationEpochs);
    }

    function _getStorage_MaxAllocationEpochs() internal view returns (uint256) {
        uint256 slot = 13;

        // Read the current value of the storage slot
        uint256 currentSlotValue = uint256(vm.load(address(staking), bytes32(slot)));

        // Mask to isolate bits 128-159
        uint256 mask = uint256(0xFFFFFFFF) << 128;

        // Extract the maxAllocationEpochs by masking and shifting
        uint256 maxAllocationEpochs = (currentSlotValue & mask) >> 128;

        return maxAllocationEpochs;
    }

    function _setStorage_DelegationPool(
        address serviceProvider,
        uint256 tokens,
        uint32 indexingRewardCut,
        uint32 queryFeeCut
    ) internal {
        bytes32 baseSlot = keccak256(abi.encode(serviceProvider, uint256(20)));
        bytes32 feeCutValues = bytes32(
            (uint256(indexingRewardCut) << uint256(32)) | (uint256(queryFeeCut) << uint256(64))
        );
        bytes32 tokensSlot = bytes32(uint256(baseSlot) + 2);
        vm.store(address(staking), baseSlot, feeCutValues);
        vm.store(address(staking), tokensSlot, bytes32(tokens));
    }

    function _setStorage_RebateParameters(
        uint32 alphaNumerator,
        uint32 alphaDenominator,
        uint32 lambdaNumerator,
        uint32 lambdaDenominator
    ) internal {
        // Store alpha numerator and denominator in slot 13
        uint256 alphaSlot = 13;
        uint256 alphaNumeratorOffset = 160; // Offset for __DEPRECATED_alphaNumerator (20th byte)
        uint256 alphaDenominatorOffset = 192; // Offset for __DEPRECATED_alphaDenominator (24th byte)

        // Read current value of the slot
        uint256 currentAlphaSlotValue = uint256(vm.load(address(staking), bytes32(alphaSlot)));

        // Create a mask to clear the bits for alphaNumerator and alphaDenominator
        uint256 alphaMask = ~(uint256(0xFFFFFFFF) << alphaNumeratorOffset) &
            ~(uint256(0xFFFFFFFF) << alphaDenominatorOffset);

        // Clear and set new values
        uint256 newAlphaSlotValue = (currentAlphaSlotValue & alphaMask) |
            (uint256(alphaNumerator) << alphaNumeratorOffset) |
            (uint256(alphaDenominator) << alphaDenominatorOffset);

        // Store the updated value back into the slot
        vm.store(address(staking), bytes32(alphaSlot), bytes32(newAlphaSlotValue));

        // Store lambda numerator and denominator in slot 25
        uint256 lambdaSlot = 25;
        uint256 lambdaNumeratorOffset = 160; // Offset for lambdaNumerator (20th byte)
        uint256 lambdaDenominatorOffset = 192; // Offset for lambdaDenominator (24th byte)

        // Read current value of the slot
        uint256 currentLambdaSlotValue = uint256(vm.load(address(staking), bytes32(lambdaSlot)));

        // Create a mask to clear the bits for lambdaNumerator and lambdaDenominator
        uint256 lambdaMask = ~(uint256(0xFFFFFFFF) << lambdaNumeratorOffset) &
            ~(uint256(0xFFFFFFFF) << lambdaDenominatorOffset);

        // Clear and set new values
        uint256 newLambdaSlotValue = (currentLambdaSlotValue & lambdaMask) |
            (uint256(lambdaNumerator) << lambdaNumeratorOffset) |
            (uint256(lambdaDenominator) << lambdaDenominatorOffset);

        // Store the updated value back into the slot
        vm.store(address(staking), bytes32(lambdaSlot), bytes32(newLambdaSlotValue));

        // Verify the storage
        (
            uint32 readAlphaNumerator,
            uint32 readAlphaDenominator,
            uint32 readLambdaNumerator,
            uint32 readLambdaDenominator
        ) = _getStorage_RebateParameters();
        assertEq(readAlphaNumerator, alphaNumerator);
        assertEq(readAlphaDenominator, alphaDenominator);
        assertEq(readLambdaNumerator, lambdaNumerator);
        assertEq(readLambdaDenominator, lambdaDenominator);
    }

    function _getStorage_RebateParameters() internal view returns (uint32, uint32, uint32, uint32) {
        // Read alpha numerator and denominator
        uint256 alphaSlot = 13;
        uint256 alphaValues = uint256(vm.load(address(staking), bytes32(alphaSlot)));
        uint32 alphaNumerator_ = uint32(alphaValues >> 160);
        uint32 alphaDenominator_ = uint32(alphaValues >> 192);

        // Read lambda numerator and denominator
        uint256 lambdaSlot = 25;
        uint256 lambdaValues = uint256(vm.load(address(staking), bytes32(lambdaSlot)));
        uint32 lambdaNumerator_ = uint32(lambdaValues >> 160);
        uint32 lambdaDenominator_ = uint32(lambdaValues >> 192);

        return (alphaNumerator_, alphaDenominator_, lambdaNumerator_, lambdaDenominator_);
    }

    // function _setStorage_ProtocolTaxAndCuration(uint32 curationPercentage, uint32 taxPercentage) private {
    //     bytes32 slot = bytes32(uint256(13));
    //     uint256 curationOffset = 4;
    //     uint256 protocolTaxOffset = 8;
    //     bytes32 originalValue = vm.load(address(staking), slot);

    //     bytes32 newProtocolTaxValue = bytes32(
    //         ((uint256(originalValue) &
    //             ~((0xFFFFFFFF << (8 * curationOffset)) | (0xFFFFFFFF << (8 * protocolTaxOffset)))) |
    //             (uint256(curationPercentage) << (8 * curationOffset))) |
    //             (uint256(taxPercentage) << (8 * protocolTaxOffset))
    //     );
    //     vm.store(address(staking), slot, newProtocolTaxValue);

    //     (uint32 readCurationPercentage, uint32 readTaxPercentage) = _getStorage_ProtocolTaxAndCuration();
    //     assertEq(readCurationPercentage, curationPercentage);
    // }

    function _setStorage_ProtocolTaxAndCuration(uint32 curationPercentage, uint32 taxPercentage) internal {
        bytes32 slot = bytes32(uint256(13));

        // Offsets for the percentages
        uint256 curationOffset = 32; // __DEPRECATED_curationPercentage (2nd uint32, bits 32-63)
        uint256 protocolTaxOffset = 64; // __DEPRECATED_protocolPercentage (3rd uint32, bits 64-95)

        // Read the current slot value
        uint256 originalValue = uint256(vm.load(address(staking), slot));

        // Create masks to clear the specific bits for the two percentages
        uint256 mask = ~(uint256(0xFFFFFFFF) << curationOffset) & ~(uint256(0xFFFFFFFF) << protocolTaxOffset); // Mask for curationPercentage // Mask for protocolTax

        // Clear the existing bits and set the new values
        uint256 newSlotValue = (originalValue & mask) |
            (uint256(curationPercentage) << curationOffset) |
            (uint256(taxPercentage) << protocolTaxOffset);

        // Store the updated slot value
        vm.store(address(staking), slot, bytes32(newSlotValue));

        // Verify the values were set correctly
        (uint32 readCurationPercentage, uint32 readTaxPercentage) = _getStorage_ProtocolTaxAndCuration();
        assertEq(readCurationPercentage, curationPercentage);
        assertEq(readTaxPercentage, taxPercentage);
    }

    function _getStorage_ProtocolTaxAndCuration() internal view returns (uint32, uint32) {
        bytes32 slot = bytes32(uint256(13));
        bytes32 value = vm.load(address(staking), slot);
        uint32 curationPercentage = uint32(uint256(value) >> 32);
        uint32 taxPercentage = uint32(uint256(value) >> 64);
        return (curationPercentage, taxPercentage);
    }

    /*
     * MISC: private functions to help with testing
     */
    function calcThawRequestData(
        address serviceProvider,
        address verifier,
        address owner,
        uint256 iterations,
        bool delegation
    ) private view returns (uint256, uint256, uint256, ThawRequest[] memory, bytes32[] memory, uint256[] memory) {
        LinkedList.List memory thawRequestList = staking.getThawRequestList(serviceProvider, verifier, owner);
        if (thawRequestList.count == 0) {
            return (0, 0, 0, new ThawRequest[](0), new bytes32[](0), new uint256[](0));
        }

        Provision memory prov = staking.getProvision(serviceProvider, verifier);
        DelegationPool memory pool = staking.getDelegationPool(serviceProvider, verifier);

        uint256 tokensThawed = 0;
        uint256 tokensThawing = delegation ? pool.tokensThawing : prov.tokensThawing;
        uint256 sharesThawing = delegation ? pool.sharesThawing : prov.sharesThawing;
        uint256 thawRequestsFulfilled = 0;

        bytes32 thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0) && (iterations == 0 || thawRequestsFulfilled < iterations)) {
            ThawRequest memory thawRequest = staking.getThawRequest(thawRequestId);
            if (thawRequest.thawingUntil <= block.timestamp) {
                thawRequestsFulfilled++;
                uint256 tokens = delegation
                    ? (thawRequest.shares * pool.tokensThawing) / pool.sharesThawing
                    : (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
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
                uint256 tokens = delegation
                    ? (thawRequest.shares * pool.tokensThawing) / pool.sharesThawing
                    : (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
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
