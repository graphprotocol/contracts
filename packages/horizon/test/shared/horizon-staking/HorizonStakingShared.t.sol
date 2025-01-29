// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingBase } from "../../../contracts/interfaces/internal/IHorizonStakingBase.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";
import { IHorizonStakingTypes } from "../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";

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
        _setOperator(subgraphDataServiceAddress, users.operator, true);
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
        vm.assume(maxVerifierCut <= MAX_PPM);
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
        emit IHorizonStakingBase.HorizonStakeDeposited(serviceProvider, tokens);
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
            emit IHorizonStakingMain.HorizonStakeWithdrawn(msgSender, _tokens);
        } else {
            if (withdrawCalled) {
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.HorizonStakeWithdrawn(msgSender, beforeServiceProvider.__DEPRECATED_tokensLocked);
            }

            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.HorizonStakeLocked(
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
        emit IHorizonStakingMain.HorizonStakeWithdrawn(msgSender, beforeServiceProvider.__DEPRECATED_tokensLocked);
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
        assertEq(afterProvision.thawingNonce, 0);
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
        assertEq(afterProvision.thawingNonce, beforeProvision.thawingNonce);
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
            IHorizonStakingTypes.ThawRequestType.Provision,
            serviceProvider,
            verifier,
            serviceProvider
        );

        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(users.indexer, verifier, users.indexer, beforeThawRequestList.nonce)
        );
        uint256 thawingShares = beforeProvision.tokensThawing == 0
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
        ThawRequest memory afterThawRequest = staking.getThawRequest(IHorizonStakingTypes.ThawRequestType.Provision, thawRequestId);
        LinkedList.List memory afterThawRequestList = _getThawRequestList(IHorizonStakingTypes.ThawRequestType.Provision, serviceProvider, verifier, serviceProvider);
        ThawRequest memory afterPreviousTailThawRequest = staking.getThawRequest(IHorizonStakingTypes.ThawRequestType.Provision, beforeThawRequestList.tail);

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens);
        assertEq(afterProvision.tokensThawing, beforeProvision.tokensThawing + tokens);
        assertEq(
            afterProvision.sharesThawing,
            beforeProvision.tokensThawing == 0 ? thawingShares : beforeProvision.sharesThawing + thawingShares
        );
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);
        assertEq(afterProvision.thawingNonce, beforeProvision.thawingNonce);
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
            IHorizonStakingTypes.ThawRequestType.Provision,
            serviceProvider,
            verifier,
            serviceProvider
        );

        Params_CalcThawRequestData memory params = Params_CalcThawRequestData({
            thawRequestType: IHorizonStakingTypes.ThawRequestType.Provision,
            serviceProvider: serviceProvider,
            verifier: verifier,
            owner: serviceProvider,
            iterations: nThawRequests,
            delegation: false
        });
        CalcValues_ThawRequestData memory calcValues = calcThawRequestData(params);

        // deprovision
        for (uint i = 0; i < calcValues.thawRequestsFulfilledList.length; i++) {
            ThawRequest memory thawRequest = calcValues.thawRequestsFulfilledList[i];
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ThawRequestFulfilled(
                calcValues.thawRequestsFulfilledListIds[i],
                calcValues.thawRequestsFulfilledListTokens[i],
                thawRequest.shares,
                thawRequest.thawingUntil,
                beforeProvision.thawingNonce == thawRequest.thawingNonce
            );
        }
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawRequestsFulfilled(
            serviceProvider,
            verifier,
            serviceProvider,
            calcValues.thawRequestsFulfilledList.length,
            calcValues.tokensThawed,
            IHorizonStakingTypes.ThawRequestType.Provision
        );
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.TokensDeprovisioned(serviceProvider, verifier, calcValues.tokensThawed);
        staking.deprovision(serviceProvider, verifier, nThawRequests);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            IHorizonStakingTypes.ThawRequestType.Provision,
            serviceProvider,
            verifier,
            serviceProvider
        );

        // assert
        assertEq(afterProvision.tokens, beforeProvision.tokens - calcValues.tokensThawed);
        assertEq(afterProvision.tokensThawing, calcValues.tokensThawing);
        assertEq(afterProvision.sharesThawing, calcValues.sharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeProvision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeProvision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeProvision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeProvision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeProvision.thawingPeriodPending);
        assertEq(afterProvision.thawingNonce, beforeProvision.thawingNonce);
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked);
        assertEq(
            afterServiceProvider.tokensProvisioned,
            beforeServiceProvider.tokensProvisioned - calcValues.tokensThawed
        );
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeServiceProvider.__DEPRECATED_tokensLockedUntil
        );
        for (uint i = 0; i < calcValues.thawRequestsFulfilledListIds.length; i++) {
            ThawRequest memory thawRequest = staking.getThawRequest(IHorizonStakingTypes.ThawRequestType.Provision, calcValues.thawRequestsFulfilledListIds[i]);
            assertEq(thawRequest.shares, 0);
            assertEq(thawRequest.thawingUntil, 0);
            assertEq(thawRequest.next, bytes32(0));
        }
        if (calcValues.thawRequestsFulfilledList.length == 0) {
            assertEq(afterThawRequestList.head, beforeThawRequestList.head);
        } else {
            assertEq(
                afterThawRequestList.head,
                calcValues.thawRequestsFulfilledList.length == beforeThawRequestList.count
                    ? bytes32(0)
                    : calcValues.thawRequestsFulfilledList[calcValues.thawRequestsFulfilledList.length - 1].next
            );
        }
        assertEq(
            afterThawRequestList.tail,
            calcValues.thawRequestsFulfilledList.length == beforeThawRequestList.count
                ? bytes32(0)
                : beforeThawRequestList.tail
        );
        assertEq(afterThawRequestList.count, beforeThawRequestList.count - calcValues.thawRequestsFulfilledList.length);
        assertEq(afterThawRequestList.nonce, beforeThawRequestList.nonce);
    }

    struct BeforeValues_Reprovision {
        Provision provision;
        Provision provisionNewVerifier;
        ServiceProviderInternal serviceProvider;
        LinkedList.List thawRequestList;
    }

    function _reprovision(
        address serviceProvider,
        address verifier,
        address newVerifier,
        uint256 nThawRequests
    ) internal {
        // before
        BeforeValues_Reprovision memory beforeValues = BeforeValues_Reprovision({
            provision: staking.getProvision(serviceProvider, verifier),
            provisionNewVerifier: staking.getProvision(serviceProvider, newVerifier),
            serviceProvider: _getStorage_ServiceProviderInternal(serviceProvider),
            thawRequestList: staking.getThawRequestList(IHorizonStakingTypes.ThawRequestType.Provision, serviceProvider, verifier, serviceProvider)
        });

        // calc
        Params_CalcThawRequestData memory params = Params_CalcThawRequestData({
            thawRequestType: IHorizonStakingTypes.ThawRequestType.Provision,
            serviceProvider: serviceProvider,
            verifier: verifier,
            owner: serviceProvider,
            iterations: nThawRequests,
            delegation: false
        });
        CalcValues_ThawRequestData memory calcValues = calcThawRequestData(params);

        // reprovision
        for (uint i = 0; i < calcValues.thawRequestsFulfilledList.length; i++) {
            ThawRequest memory thawRequest = calcValues.thawRequestsFulfilledList[i];
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ThawRequestFulfilled(
                calcValues.thawRequestsFulfilledListIds[i],
                calcValues.thawRequestsFulfilledListTokens[i],
                thawRequest.shares,
                thawRequest.thawingUntil,
                beforeValues.provision.thawingNonce == thawRequest.thawingNonce
            );
        }
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawRequestsFulfilled(
            serviceProvider,
            verifier,
            serviceProvider,
            calcValues.thawRequestsFulfilledList.length,
            calcValues.tokensThawed,
            IHorizonStakingTypes.ThawRequestType.Provision
        );
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.TokensDeprovisioned(serviceProvider, verifier, calcValues.tokensThawed);
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionIncreased(serviceProvider, newVerifier, calcValues.tokensThawed);
        staking.reprovision(serviceProvider, verifier, newVerifier, nThawRequests);

        // after
        Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        Provision memory afterProvisionNewVerifier = staking.getProvision(serviceProvider, newVerifier);
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            IHorizonStakingTypes.ThawRequestType.Provision,
            serviceProvider,
            verifier,
            serviceProvider
        );

        // assert: provision old verifier
        assertEq(afterProvision.tokens, beforeValues.provision.tokens - calcValues.tokensThawed);
        assertEq(afterProvision.tokensThawing, calcValues.tokensThawing);
        assertEq(afterProvision.sharesThawing, calcValues.sharesThawing);
        assertEq(afterProvision.maxVerifierCut, beforeValues.provision.maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, beforeValues.provision.thawingPeriod);
        assertEq(afterProvision.createdAt, beforeValues.provision.createdAt);
        assertEq(afterProvision.maxVerifierCutPending, beforeValues.provision.maxVerifierCutPending);
        assertEq(afterProvision.thawingPeriodPending, beforeValues.provision.thawingPeriodPending);
        assertEq(afterProvision.thawingNonce, beforeValues.provision.thawingNonce);

        // assert: provision new verifier
        assertEq(afterProvisionNewVerifier.tokens, beforeValues.provisionNewVerifier.tokens + calcValues.tokensThawed);
        assertEq(afterProvisionNewVerifier.tokensThawing, beforeValues.provisionNewVerifier.tokensThawing);
        assertEq(afterProvisionNewVerifier.sharesThawing, beforeValues.provisionNewVerifier.sharesThawing);
        assertEq(afterProvisionNewVerifier.maxVerifierCut, beforeValues.provisionNewVerifier.maxVerifierCut);
        assertEq(afterProvisionNewVerifier.thawingPeriod, beforeValues.provisionNewVerifier.thawingPeriod);
        assertEq(afterProvisionNewVerifier.createdAt, beforeValues.provisionNewVerifier.createdAt);
        assertEq(
            afterProvisionNewVerifier.maxVerifierCutPending,
            beforeValues.provisionNewVerifier.maxVerifierCutPending
        );
        assertEq(
            afterProvisionNewVerifier.thawingPeriodPending,
            beforeValues.provisionNewVerifier.thawingPeriodPending
        );
        assertEq(afterProvisionNewVerifier.thawingNonce, beforeValues.provisionNewVerifier.thawingNonce);

        // assert: service provider
        assertEq(afterServiceProvider.tokensStaked, beforeValues.serviceProvider.tokensStaked);
        assertEq(
            afterServiceProvider.tokensProvisioned,
            beforeValues.serviceProvider.tokensProvisioned + calcValues.tokensThawed - calcValues.tokensThawed
        );
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensAllocated,
            beforeValues.serviceProvider.__DEPRECATED_tokensAllocated
        );
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLocked,
            beforeValues.serviceProvider.__DEPRECATED_tokensLocked
        );
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeValues.serviceProvider.__DEPRECATED_tokensLockedUntil
        );

        // assert: thaw request list old verifier
        for (uint i = 0; i < calcValues.thawRequestsFulfilledListIds.length; i++) {
            ThawRequest memory thawRequest = staking.getThawRequest(IHorizonStakingTypes.ThawRequestType.Provision, calcValues.thawRequestsFulfilledListIds[i]);
            assertEq(thawRequest.shares, 0);
            assertEq(thawRequest.thawingUntil, 0);
            assertEq(thawRequest.next, bytes32(0));
        }
        if (calcValues.thawRequestsFulfilledList.length == 0) {
            assertEq(afterThawRequestList.head, beforeValues.thawRequestList.head);
        } else {
            assertEq(
                afterThawRequestList.head,
                calcValues.thawRequestsFulfilledList.length == beforeValues.thawRequestList.count
                    ? bytes32(0)
                    : calcValues.thawRequestsFulfilledList[calcValues.thawRequestsFulfilledList.length - 1].next
            );
        }
        assertEq(
            afterThawRequestList.tail,
            calcValues.thawRequestsFulfilledList.length == beforeValues.thawRequestList.count
                ? bytes32(0)
                : beforeValues.thawRequestList.tail
        );
        assertEq(
            afterThawRequestList.count,
            beforeValues.thawRequestList.count - calcValues.thawRequestsFulfilledList.length
        );
        assertEq(afterThawRequestList.nonce, beforeValues.thawRequestList.nonce);
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
        assertEq(afterProvision.thawingNonce, beforeProvision.thawingNonce);
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
        assertEq(afterProvision.thawingNonce, beforeProvision.thawingNonce);
    }

    function _setOperator(address verifier, address operator, bool allow) internal {
        __setOperator(verifier, operator, allow, false);
    }

    function _setOperatorLocked(address verifier, address operator, bool allow) internal {
        __setOperator(verifier, operator, allow, true);
    }

    function __setOperator(address verifier, address operator, bool allow, bool locked) private {
        (, address msgSender, ) = vm.readCallers();

        // staking contract knows the address of the legacy subgraph service
        // but we cannot read it as it's an immutable, we have to use the global var :/
        bool legacy = verifier == subgraphDataServiceLegacyAddress;

        // before
        bool beforeOperatorAllowed = _getStorage_OperatorAuth(msgSender, verifier, operator, legacy);
        bool beforeOperatorAllowedGetter = staking.isAuthorized(msgSender, verifier, operator);
        assertEq(beforeOperatorAllowed, beforeOperatorAllowedGetter);

        // setOperator
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.OperatorSet(msgSender, verifier, operator, allow);
        if (locked) {
            staking.setOperatorLocked(verifier, operator, allow);
        } else {
            staking.setOperator(verifier, operator, allow);
        }

        // after
        bool afterOperatorAllowed = _getStorage_OperatorAuth(msgSender, verifier, operator, legacy);
        bool afterOperatorAllowedGetter = staking.isAuthorized(msgSender, verifier, operator);
        assertEq(afterOperatorAllowed, afterOperatorAllowedGetter, "afterOperatorAllowedGetter FAIL");

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
        emit IHorizonStakingMain.TokensDelegated(serviceProvider, verifier, delegator, tokens, calcShares);
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
        assertEq(beforePool.tokens + tokens, afterPool.tokens, "afterPool.tokens FAIL");
        assertEq(beforePool.shares + calcShares, afterPool.shares, "afterPool.shares FAIL");
        assertEq(beforePool.tokensThawing, afterPool.tokensThawing);
        assertEq(beforePool.sharesThawing, afterPool.sharesThawing);
        assertEq(beforePool.thawingNonce, afterPool.thawingNonce);
        assertEq(beforeDelegation.shares + calcShares, afterDelegation.shares);
        assertEq(beforeDelegation.__DEPRECATED_tokensLocked, afterDelegation.__DEPRECATED_tokensLocked);
        assertEq(beforeDelegation.__DEPRECATED_tokensLockedUntil, afterDelegation.__DEPRECATED_tokensLockedUntil);
        assertGe(deltaShares, minSharesOut);
        assertEq(calcShares, deltaShares);
        assertEq(beforeDelegatorBalance - tokens, afterDelegatorBalance);
        assertEq(beforeStakingBalance + tokens, afterStakingBalance);
    }

    function _undelegate(address serviceProvider, address verifier, uint256 shares) internal {
        (, address caller, ) = vm.readCallers();
        __undelegate(IHorizonStakingTypes.ThawRequestType.Delegation, serviceProvider, verifier, shares, false, caller);
    }

    function _undelegate(address serviceProvider, uint256 shares) internal {
        (, address caller, ) = vm.readCallers();
        __undelegate(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            serviceProvider,
            subgraphDataServiceLegacyAddress,
            shares,
            true,
            caller
        );
    }

    struct BeforeValues_Undelegate {
        DelegationPoolInternalTest pool;
        DelegationInternal delegation;
        LinkedList.List thawRequestList;
        uint256 delegatedTokens;
    }
    struct CalcValues_Undelegate {
        uint256 tokens;
        uint256 thawingShares;
        uint64 thawingUntil;
        bytes32 thawRequestId;
    }

    function __undelegate(
        IHorizonStakingTypes.ThawRequestType thawRequestType,
        address serviceProvider,
        address verifier,
        uint256 shares,
        bool legacy,
        address beneficiary
    ) private {
        (, address delegator, ) = vm.readCallers();

        // before
        BeforeValues_Undelegate memory beforeValues;
        beforeValues.pool = _getStorage_DelegationPoolInternal(serviceProvider, verifier, legacy);
        beforeValues.delegation = _getStorage_Delegation(serviceProvider, verifier, delegator, legacy);
        beforeValues.thawRequestList = staking.getThawRequestList(thawRequestType, serviceProvider, verifier, delegator);
        beforeValues.delegatedTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);

        // calc
        CalcValues_Undelegate memory calcValues;
        calcValues.tokens =
            ((beforeValues.pool.tokens - beforeValues.pool.tokensThawing) * shares) /
            beforeValues.pool.shares;
        calcValues.thawingShares = beforeValues.pool.tokensThawing == 0
            ? calcValues.tokens
            : (beforeValues.pool.sharesThawing * calcValues.tokens) / beforeValues.pool.tokensThawing;
        calcValues.thawingUntil =
            staking.getProvision(serviceProvider, verifier).thawingPeriod +
            uint64(block.timestamp);
        calcValues.thawRequestId = keccak256(
            abi.encodePacked(serviceProvider, verifier, beneficiary, beforeValues.thawRequestList.nonce)
        );

        // undelegate
        vm.expectEmit();
        emit IHorizonStakingMain.ThawRequestCreated(
            serviceProvider,
            verifier,
            beneficiary,
            calcValues.thawingShares,
            calcValues.thawingUntil,
            calcValues.thawRequestId
        );
        vm.expectEmit();
        emit IHorizonStakingMain.TokensUndelegated(serviceProvider, verifier, delegator, calcValues.tokens);
        if (legacy) {
            staking.undelegate(serviceProvider, shares);
        } else if (thawRequestType == IHorizonStakingTypes.ThawRequestType.Delegation) {
            staking.undelegate(serviceProvider, verifier, shares);
        } else {
            revert("Invalid thaw request type");
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
            beneficiary,
            legacy
        );
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(thawRequestType, serviceProvider, verifier, beneficiary);
        ThawRequest memory afterThawRequest = staking.getThawRequest(thawRequestType, calcValues.thawRequestId);
        uint256 afterDelegatedTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);

        // assertions
        assertEq(beforeValues.pool.shares, afterPool.shares + shares);
        assertEq(beforeValues.pool.tokens, afterPool.tokens);
        assertEq(beforeValues.pool.tokensThawing + calcValues.tokens, afterPool.tokensThawing);
        assertEq(
            beforeValues.pool.tokensThawing == 0
                ? calcValues.thawingShares
                : beforeValues.pool.sharesThawing + calcValues.thawingShares,
            afterPool.sharesThawing
        );
        assertEq(beforeValues.pool.thawingNonce, afterPool.thawingNonce);
        assertEq(beforeValues.delegation.shares - shares, afterDelegation.shares);
        assertEq(afterThawRequest.shares, calcValues.thawingShares);
        assertEq(afterThawRequest.thawingUntil, calcValues.thawingUntil);
        assertEq(afterThawRequest.next, bytes32(0));
        assertEq(calcValues.thawRequestId, afterThawRequestList.tail);
        assertEq(beforeValues.thawRequestList.nonce + 1, afterThawRequestList.nonce);
        assertEq(beforeValues.thawRequestList.count + 1, afterThawRequestList.count);
        assertEq(afterDelegatedTokens + calcValues.tokens, beforeValues.delegatedTokens);
    }

    function _withdrawDelegated(
        address serviceProvider,
        address verifier,
        uint256 nThawRequests
    ) internal {
        Params_WithdrawDelegated memory params = Params_WithdrawDelegated({
            thawRequestType: IHorizonStakingTypes.ThawRequestType.Delegation,
            serviceProvider: serviceProvider,
            verifier: verifier,
            newServiceProvider: address(0),
            newVerifier: address(0),
            minSharesForNewProvider: 0,
            nThawRequests: nThawRequests,
            legacy: verifier == subgraphDataServiceLegacyAddress
        });
        __withdrawDelegated(params);
    }

    function _redelegate(
        address serviceProvider,
        address verifier,
        address newServiceProvider,
        address newVerifier,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) internal {
        Params_WithdrawDelegated memory params = Params_WithdrawDelegated({
            thawRequestType: IHorizonStakingTypes.ThawRequestType.Delegation,
            serviceProvider: serviceProvider,
            verifier: verifier,
            newServiceProvider: newServiceProvider,
            newVerifier: newVerifier,
            minSharesForNewProvider: minSharesForNewProvider,
            nThawRequests: nThawRequests,
            legacy: false
        });
        __withdrawDelegated(params);
    }

    struct BeforeValues_WithdrawDelegated {
        DelegationPoolInternalTest pool;
        DelegationPoolInternalTest newPool;
        DelegationInternal newDelegation;
        LinkedList.List thawRequestList;
        uint256 senderBalance;
        uint256 stakingBalance;
    }
    struct AfterValues_WithdrawDelegated {
        DelegationPoolInternalTest pool;
        DelegationPoolInternalTest newPool;
        DelegationInternal newDelegation;
        LinkedList.List thawRequestList;
        uint256 senderBalance;
        uint256 stakingBalance;
    }

    struct Params_WithdrawDelegated {
        IHorizonStakingTypes.ThawRequestType thawRequestType;
        address serviceProvider;
        address verifier;
        address newServiceProvider;
        address newVerifier;
        uint256 minSharesForNewProvider;
        uint256 nThawRequests;
        bool legacy;
    }

    function __withdrawDelegated(Params_WithdrawDelegated memory params) private {
        (, address msgSender, ) = vm.readCallers();

        bool reDelegate = params.newServiceProvider != address(0) && params.newVerifier != address(0);

        // before
        BeforeValues_WithdrawDelegated memory beforeValues;
        beforeValues.pool = _getStorage_DelegationPoolInternal(params.serviceProvider, params.verifier, params.legacy);
        beforeValues.newPool = _getStorage_DelegationPoolInternal(params.newServiceProvider, params.newVerifier, params.legacy);
        beforeValues.newDelegation = _getStorage_Delegation(params.newServiceProvider, params.newVerifier, msgSender, params.legacy);
        beforeValues.thawRequestList = staking.getThawRequestList(params.thawRequestType, params.serviceProvider, params.verifier, msgSender);
        beforeValues.senderBalance = token.balanceOf(msgSender);
        beforeValues.stakingBalance = token.balanceOf(address(staking));

        Params_CalcThawRequestData memory paramsCalc = Params_CalcThawRequestData({
            thawRequestType: params.thawRequestType,
            serviceProvider: params.serviceProvider,
            verifier: params.verifier,
            owner: msgSender,
            iterations: params.nThawRequests,
            delegation: true
        });
        CalcValues_ThawRequestData memory calcValues = calcThawRequestData(paramsCalc);

        // withdrawDelegated
        for (uint i = 0; i < calcValues.thawRequestsFulfilledList.length; i++) {
            ThawRequest memory thawRequest = calcValues.thawRequestsFulfilledList[i];
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ThawRequestFulfilled(
                calcValues.thawRequestsFulfilledListIds[i],
                calcValues.thawRequestsFulfilledListTokens[i],
                thawRequest.shares,
                thawRequest.thawingUntil,
                beforeValues.pool.thawingNonce == thawRequest.thawingNonce
            );
        }
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.ThawRequestsFulfilled(
            params.serviceProvider,
            params.verifier,
            msgSender,
            calcValues.thawRequestsFulfilledList.length,
            calcValues.tokensThawed,
            params.thawRequestType
        );
        if (calcValues.tokensThawed != 0) {
            vm.expectEmit();
            if (reDelegate) {
                emit IHorizonStakingMain.TokensDelegated(
                    params.newServiceProvider,
                    params.newVerifier,
                    msgSender,
                    calcValues.tokensThawed,
                    calcValues.sharesThawed
                );
            } else {
                emit Transfer(address(staking), msgSender, calcValues.tokensThawed);
                
                vm.expectEmit();
                emit IHorizonStakingMain.DelegatedTokensWithdrawn(
                    params.serviceProvider,
                    params.verifier,
                    msgSender,
                    calcValues.tokensThawed
                );
            }
        }

        if (reDelegate) {
            staking.redelegate(
                params.serviceProvider,
                params.verifier,
                params.newServiceProvider,
                params.newVerifier,
                params.minSharesForNewProvider,
                params.nThawRequests
            );
        } else if (params.thawRequestType == IHorizonStakingTypes.ThawRequestType.Delegation) {
            staking.withdrawDelegated(params.serviceProvider, params.verifier, params.nThawRequests);
        } else {
            revert("Invalid thaw request type");
        }

        // after
        AfterValues_WithdrawDelegated memory afterValues;
        afterValues.pool = _getStorage_DelegationPoolInternal(params.serviceProvider, params.verifier, params.legacy);
        afterValues.newPool = _getStorage_DelegationPoolInternal(params.newServiceProvider, params.newVerifier, params.legacy);
        afterValues.newDelegation = _getStorage_Delegation(params.newServiceProvider, params.newVerifier, msgSender, params.legacy);
        afterValues.thawRequestList = staking.getThawRequestList(params.thawRequestType, params.serviceProvider, params.verifier, msgSender);
        afterValues.senderBalance = token.balanceOf(msgSender);
        afterValues.stakingBalance = token.balanceOf(address(staking));

        // assert
        assertEq(afterValues.pool.tokens, beforeValues.pool.tokens - calcValues.tokensThawed);
        assertEq(afterValues.pool.shares, beforeValues.pool.shares);
        assertEq(afterValues.pool.tokensThawing, calcValues.tokensThawing);
        assertEq(afterValues.pool.sharesThawing, calcValues.sharesThawing);
        assertEq(afterValues.pool.thawingNonce, beforeValues.pool.thawingNonce);

        for (uint i = 0; i < calcValues.thawRequestsFulfilledListIds.length; i++) {
            ThawRequest memory thawRequest = staking.getThawRequest(params.thawRequestType, calcValues.thawRequestsFulfilledListIds[i]);
            assertEq(thawRequest.shares, 0);
            assertEq(thawRequest.thawingUntil, 0);
            assertEq(thawRequest.next, bytes32(0));
        }
        if (calcValues.thawRequestsFulfilledList.length == 0) {
            assertEq(afterValues.thawRequestList.head, beforeValues.thawRequestList.head);
        } else {
            assertEq(
                afterValues.thawRequestList.head,
                calcValues.thawRequestsFulfilledList.length == beforeValues.thawRequestList.count
                    ? bytes32(0)
                    : calcValues.thawRequestsFulfilledList[calcValues.thawRequestsFulfilledList.length - 1].next
            );
        }
        assertEq(
            afterValues.thawRequestList.tail,
            calcValues.thawRequestsFulfilledList.length == beforeValues.thawRequestList.count
                ? bytes32(0)
                : beforeValues.thawRequestList.tail
        );
        assertEq(
            afterValues.thawRequestList.count,
            beforeValues.thawRequestList.count - calcValues.thawRequestsFulfilledList.length
        );
        assertEq(afterValues.thawRequestList.nonce, beforeValues.thawRequestList.nonce);

        if (reDelegate) {
            uint256 calcShares = (afterValues.newPool.tokens == 0 ||
                afterValues.newPool.tokens == afterValues.newPool.tokensThawing)
                ? calcValues.tokensThawed
                : ((calcValues.tokensThawed * afterValues.newPool.shares) /
                    (afterValues.newPool.tokens - afterValues.newPool.tokensThawing));
            uint256 deltaShares = afterValues.newDelegation.shares - beforeValues.newDelegation.shares;

            assertEq(afterValues.newPool.tokens, beforeValues.newPool.tokens + calcValues.tokensThawed);
            assertEq(afterValues.newPool.shares, beforeValues.newPool.shares + calcShares);
            assertEq(afterValues.newPool.tokensThawing, beforeValues.newPool.tokensThawing);
            assertEq(afterValues.newPool.sharesThawing, beforeValues.newPool.sharesThawing);
            assertEq(afterValues.newDelegation.shares, beforeValues.newDelegation.shares + calcShares);
            assertEq(
                afterValues.newDelegation.__DEPRECATED_tokensLocked,
                beforeValues.newDelegation.__DEPRECATED_tokensLocked
            );
            assertEq(
                afterValues.newDelegation.__DEPRECATED_tokensLockedUntil,
                beforeValues.newDelegation.__DEPRECATED_tokensLockedUntil
            );
            assertGe(deltaShares, params.minSharesForNewProvider);
            assertEq(calcShares, deltaShares);
            assertEq(afterValues.senderBalance - beforeValues.senderBalance, 0);
            assertEq(beforeValues.stakingBalance - afterValues.stakingBalance, 0);
        } else {
            assertEq(beforeValues.stakingBalance - afterValues.stakingBalance, calcValues.tokensThawed);
            assertEq(afterValues.senderBalance - beforeValues.senderBalance, calcValues.tokensThawed);
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
        assertEq(beforePool.thawingNonce, afterPool.thawingNonce);
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
        emit IHorizonStakingMain.DelegationSlashingEnabled();
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

    struct BeforeValues_Slash {
        Provision provision;
        DelegationPoolInternalTest pool;
        ServiceProviderInternal serviceProvider;
        uint256 stakingBalance;
        uint256 verifierBalance;
    }
    struct CalcValues_Slash {
        uint256 tokensToSlash;
        uint256 providerTokensSlashed;
        uint256 delegationTokensSlashed;
    }

    function _slash(address serviceProvider, address verifier, uint256 tokens, uint256 verifierCutAmount) internal {
        bool isDelegationSlashingEnabled = staking.isDelegationSlashingEnabled();

        // staking contract knows the address of the legacy subgraph service
        // but we cannot read it as it's an immutable, we have to use the global var :/
        bool legacy = verifier == subgraphDataServiceLegacyAddress;

        // before
        BeforeValues_Slash memory before;
        before.provision = staking.getProvision(serviceProvider, verifier);
        before.pool = _getStorage_DelegationPoolInternal(serviceProvider, verifier, legacy);
        before.serviceProvider = _getStorage_ServiceProviderInternal(serviceProvider);
        before.stakingBalance = token.balanceOf(address(staking));
        before.verifierBalance = token.balanceOf(verifier);

        // Calculate expected tokens after slashing
        CalcValues_Slash memory calcValues;
        calcValues.tokensToSlash = MathUtils.min(tokens, before.provision.tokens + before.pool.tokens);
        calcValues.providerTokensSlashed = MathUtils.min(before.provision.tokens, calcValues.tokensToSlash);
        calcValues.delegationTokensSlashed = calcValues.tokensToSlash - calcValues.providerTokensSlashed;

        if (calcValues.tokensToSlash > 0) {
            if (verifierCutAmount > 0) {
                vm.expectEmit(address(token));
                emit Transfer(address(staking), verifier, verifierCutAmount);
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.VerifierTokensSent(serviceProvider, verifier, verifier, verifierCutAmount);
            }
            if (calcValues.providerTokensSlashed - verifierCutAmount > 0) {
                vm.expectEmit(address(token));
                emit Transfer(address(staking), address(0), calcValues.providerTokensSlashed - verifierCutAmount);
            }
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.ProvisionSlashed(serviceProvider, verifier, calcValues.providerTokensSlashed);
        }

        if (calcValues.delegationTokensSlashed > 0) {
            if (isDelegationSlashingEnabled) {
                vm.expectEmit(address(token));
                emit Transfer(address(staking), address(0), calcValues.delegationTokensSlashed);
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.DelegationSlashed(
                    serviceProvider,
                    verifier,
                    calcValues.delegationTokensSlashed
                );
            } else {
                vm.expectEmit(address(staking));
                emit IHorizonStakingMain.DelegationSlashingSkipped(
                    serviceProvider,
                    verifier,
                    calcValues.delegationTokensSlashed
                );
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

        {
            uint256 tokensSlashed = calcValues.providerTokensSlashed +
                (isDelegationSlashingEnabled ? calcValues.delegationTokensSlashed : 0);
            uint256 provisionThawingTokens = (before.provision.tokensThawing *
                (1e18 - ((calcValues.providerTokensSlashed * 1e18 + before.provision.tokens - 1) / before.provision.tokens))) / (1e18);

            // assert
            assertEq(afterProvision.tokens + calcValues.providerTokensSlashed, before.provision.tokens);
            assertEq(afterProvision.tokensThawing, provisionThawingTokens);
            assertEq(
                afterProvision.sharesThawing,
                afterProvision.tokensThawing == 0 ? 0 : before.provision.sharesThawing
            );
            assertEq(afterProvision.maxVerifierCut, before.provision.maxVerifierCut);
            assertEq(afterProvision.maxVerifierCutPending, before.provision.maxVerifierCutPending);
            assertEq(afterProvision.thawingPeriod, before.provision.thawingPeriod);
            assertEq(afterProvision.thawingPeriodPending, before.provision.thawingPeriodPending);
            assertEq(
                afterProvision.thawingNonce, 
                (before.provision.sharesThawing != 0 && afterProvision.sharesThawing == 0) ? before.provision.thawingNonce + 1 : before.provision.thawingNonce);
            if (isDelegationSlashingEnabled) {
                uint256 poolThawingTokens = (before.pool.tokensThawing *
                    (1e18 - ((calcValues.delegationTokensSlashed * 1e18 + before.pool.tokens - 1) / before.pool.tokens))) / (1e18);
                assertEq(afterPool.tokens + calcValues.delegationTokensSlashed, before.pool.tokens);
                assertEq(afterPool.shares, before.pool.shares);
                assertEq(afterPool.tokensThawing, poolThawingTokens);
                assertEq(afterPool.sharesThawing, afterPool.tokensThawing == 0 ? 0 : before.pool.sharesThawing);
                assertEq(afterPool.thawingNonce, (before.pool.sharesThawing != 0 && afterPool.sharesThawing == 0) ? before.pool.thawingNonce + 1 : before.pool.thawingNonce);
            }

            assertEq(before.stakingBalance - tokensSlashed, afterStakingBalance);
            assertEq(before.verifierBalance + verifierCutAmount, afterVerifierBalance);

            assertEq(
                afterServiceProvider.tokensStaked + calcValues.providerTokensSlashed,
                before.serviceProvider.tokensStaked
            );
            assertEq(
                afterServiceProvider.tokensProvisioned + calcValues.providerTokensSlashed,
                before.serviceProvider.tokensProvisioned
            );
        }
    }

    // use struct to avoid 'stack too deep' error
    struct CalcValues_CloseAllocation {
        uint256 rewards;
        uint256 delegatorRewards;
        uint256 indexerRewards;
    }
    struct BeforeValues_CloseAllocation {
        IHorizonStakingExtension.Allocation allocation;
        DelegationPoolInternalTest pool;
        ServiceProviderInternal serviceProvider;
        uint256 subgraphAllocations;
        uint256 stakingBalance;
        uint256 indexerBalance;
        uint256 beneficiaryBalance;
    }

    // Current rewards manager is mocked and assumed to mint fixed rewards
    function _closeAllocation(address allocationId, bytes32 poi) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        BeforeValues_CloseAllocation memory beforeValues;
        beforeValues.allocation = staking.getAllocation(allocationId);
        beforeValues.pool = _getStorage_DelegationPoolInternal(
            beforeValues.allocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        beforeValues.serviceProvider = _getStorage_ServiceProviderInternal(beforeValues.allocation.indexer);
        beforeValues.subgraphAllocations = _getStorage_SubgraphAllocations(
            beforeValues.allocation.subgraphDeploymentID
        );
        beforeValues.stakingBalance = token.balanceOf(address(staking));
        beforeValues.indexerBalance = token.balanceOf(beforeValues.allocation.indexer);
        beforeValues.beneficiaryBalance = token.balanceOf(
            _getStorage_RewardsDestination(beforeValues.allocation.indexer)
        );

        bool isAuth = staking.isAuthorized(
            beforeValues.allocation.indexer,
            subgraphDataServiceLegacyAddress,
            msgSender
        );
        address rewardsDestination = _getStorage_RewardsDestination(beforeValues.allocation.indexer);

        CalcValues_CloseAllocation memory calcValues = CalcValues_CloseAllocation({
            rewards: ALLOCATIONS_REWARD_CUT,
            delegatorRewards: ALLOCATIONS_REWARD_CUT -
                uint256(beforeValues.pool.__DEPRECATED_indexingRewardCut).mulPPM(ALLOCATIONS_REWARD_CUT),
            indexerRewards: 0
        });
        calcValues.indexerRewards =
            ALLOCATIONS_REWARD_CUT -
            (beforeValues.pool.tokens > 0 ? calcValues.delegatorRewards : 0);

        // closeAllocation
        vm.expectEmit(address(staking));
        emit IHorizonStakingExtension.AllocationClosed(
            beforeValues.allocation.indexer,
            beforeValues.allocation.subgraphDeploymentID,
            epochManager.currentEpoch(),
            beforeValues.allocation.tokens,
            allocationId,
            msgSender,
            poi,
            !isAuth
        );
        staking.closeAllocation(allocationId, poi);

        // after
        IHorizonStakingExtension.Allocation memory afterAllocation = staking.getAllocation(allocationId);
        DelegationPoolInternalTest memory afterPool = _getStorage_DelegationPoolInternal(
            beforeValues.allocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            beforeValues.allocation.indexer
        );
        uint256 afterSubgraphAllocations = _getStorage_SubgraphAllocations(
            beforeValues.allocation.subgraphDeploymentID
        );
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterIndexerBalance = token.balanceOf(beforeValues.allocation.indexer);
        uint256 afterBeneficiaryBalance = token.balanceOf(rewardsDestination);

        if (beforeValues.allocation.tokens > 0) {
            if (isAuth && poi != 0) {
                if (rewardsDestination != address(0)) {
                    assertEq(
                        beforeValues.stakingBalance + calcValues.rewards - calcValues.indexerRewards,
                        afterStakingBalance
                    );
                    assertEq(beforeValues.indexerBalance, afterIndexerBalance);
                    assertEq(beforeValues.beneficiaryBalance + calcValues.indexerRewards, afterBeneficiaryBalance);
                } else {
                    assertEq(beforeValues.stakingBalance + calcValues.rewards, afterStakingBalance);
                    assertEq(beforeValues.indexerBalance, afterIndexerBalance);
                    assertEq(beforeValues.beneficiaryBalance, afterBeneficiaryBalance);
                }
            } else {
                assertEq(beforeValues.stakingBalance, afterStakingBalance);
                assertEq(beforeValues.indexerBalance, afterIndexerBalance);
                assertEq(beforeValues.beneficiaryBalance, afterBeneficiaryBalance);
            }
        } else {
            assertEq(beforeValues.stakingBalance, afterStakingBalance);
            assertEq(beforeValues.indexerBalance, afterIndexerBalance);
            assertEq(beforeValues.beneficiaryBalance, afterBeneficiaryBalance);
        }

        assertEq(afterAllocation.indexer, beforeValues.allocation.indexer);
        assertEq(afterAllocation.subgraphDeploymentID, beforeValues.allocation.subgraphDeploymentID);
        assertEq(afterAllocation.tokens, beforeValues.allocation.tokens);
        assertEq(afterAllocation.createdAtEpoch, beforeValues.allocation.createdAtEpoch);
        assertEq(afterAllocation.closedAtEpoch, epochManager.currentEpoch());
        assertEq(afterAllocation.collectedFees, beforeValues.allocation.collectedFees);
        assertEq(
            afterAllocation.__DEPRECATED_effectiveAllocation,
            beforeValues.allocation.__DEPRECATED_effectiveAllocation
        );
        assertEq(afterAllocation.accRewardsPerAllocatedToken, beforeValues.allocation.accRewardsPerAllocatedToken);
        assertEq(afterAllocation.distributedRebates, beforeValues.allocation.distributedRebates);

        if (beforeValues.allocation.tokens > 0 && isAuth && poi != 0 && rewardsDestination == address(0)) {
            assertEq(
                afterServiceProvider.tokensStaked,
                beforeValues.serviceProvider.tokensStaked + calcValues.indexerRewards
            );
        } else {
            assertEq(afterServiceProvider.tokensStaked, beforeValues.serviceProvider.tokensStaked);
        }
        assertEq(afterServiceProvider.tokensProvisioned, beforeValues.serviceProvider.tokensProvisioned);
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensAllocated + beforeValues.allocation.tokens,
            beforeValues.serviceProvider.__DEPRECATED_tokensAllocated
        );
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLocked,
            beforeValues.serviceProvider.__DEPRECATED_tokensLocked
        );
        assertEq(
            afterServiceProvider.__DEPRECATED_tokensLockedUntil,
            beforeValues.serviceProvider.__DEPRECATED_tokensLockedUntil
        );

        assertEq(afterSubgraphAllocations + beforeValues.allocation.tokens, beforeValues.subgraphAllocations);

        if (beforeValues.allocation.tokens > 0 && isAuth && poi != 0 && beforeValues.pool.tokens > 0) {
            assertEq(afterPool.tokens, beforeValues.pool.tokens + calcValues.delegatorRewards);
        } else {
            assertEq(afterPool.tokens, beforeValues.pool.tokens);
        }
    }

    // use struct to avoid 'stack too deep' error
    struct BeforeValues_Collect {
        IHorizonStakingExtension.Allocation allocation;
        DelegationPoolInternalTest pool;
        ServiceProviderInternal serviceProvider;
        uint256 stakingBalance;
        uint256 senderBalance;
        uint256 curationBalance;
        uint256 beneficiaryBalance;
    }
    struct CalcValues_Collect {
        uint256 protocolTaxTokens;
        uint256 queryFees;
        uint256 curationCutTokens;
        uint256 newRebates;
        uint256 payment;
        uint256 delegationFeeCut;
    }
    struct AfterValues_Collect {
        IHorizonStakingExtension.Allocation allocation;
        DelegationPoolInternalTest pool;
        ServiceProviderInternal serviceProvider;
        uint256 stakingBalance;
        uint256 senderBalance;
        uint256 curationBalance;
        uint256 beneficiaryBalance;
    }

    function _collect(uint256 tokens, address allocationId) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        BeforeValues_Collect memory beforeValues;
        beforeValues.allocation = staking.getAllocation(allocationId);
        beforeValues.pool = _getStorage_DelegationPoolInternal(
            beforeValues.allocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        beforeValues.serviceProvider = _getStorage_ServiceProviderInternal(beforeValues.allocation.indexer);

        (uint32 curationPercentage, uint32 protocolPercentage) = _getStorage_ProtocolTaxAndCuration();
        address rewardsDestination = _getStorage_RewardsDestination(beforeValues.allocation.indexer);

        beforeValues.stakingBalance = token.balanceOf(address(staking));
        beforeValues.senderBalance = token.balanceOf(msgSender);
        beforeValues.curationBalance = token.balanceOf(address(curation));
        beforeValues.beneficiaryBalance = token.balanceOf(rewardsDestination);

        // calc some stuff
        CalcValues_Collect memory calcValues;
        calcValues.protocolTaxTokens = tokens.mulPPMRoundUp(protocolPercentage);
        calcValues.queryFees = tokens - calcValues.protocolTaxTokens;
        calcValues.curationCutTokens = 0;
        if (curation.isCurated(beforeValues.allocation.subgraphDeploymentID)) {
            calcValues.curationCutTokens = calcValues.queryFees.mulPPMRoundUp(curationPercentage);
            calcValues.queryFees -= calcValues.curationCutTokens;
        }
        calcValues.newRebates = ExponentialRebates.exponentialRebates(
            calcValues.queryFees + beforeValues.allocation.collectedFees,
            beforeValues.allocation.tokens,
            alphaNumerator,
            alphaDenominator,
            lambdaNumerator,
            lambdaDenominator
        );
        calcValues.payment = calcValues.newRebates > calcValues.queryFees
            ? calcValues.queryFees
            : calcValues.newRebates;
        calcValues.delegationFeeCut = 0;
        if (beforeValues.pool.tokens > 0) {
            calcValues.delegationFeeCut =
                calcValues.payment -
                calcValues.payment.mulPPM(beforeValues.pool.__DEPRECATED_queryFeeCut);
            calcValues.payment -= calcValues.delegationFeeCut;
        }

        // staking.collect()
        if (tokens > 0) {
            vm.expectEmit(address(staking));
            emit IHorizonStakingExtension.RebateCollected(
                msgSender,
                beforeValues.allocation.indexer,
                beforeValues.allocation.subgraphDeploymentID,
                allocationId,
                epochManager.currentEpoch(),
                tokens,
                calcValues.protocolTaxTokens,
                calcValues.curationCutTokens,
                calcValues.queryFees,
                calcValues.payment,
                calcValues.delegationFeeCut
            );
        }
        staking.collect(tokens, allocationId);

        // after
        AfterValues_Collect memory afterValues;
        afterValues.allocation = staking.getAllocation(allocationId);
        afterValues.pool = _getStorage_DelegationPoolInternal(
            beforeValues.allocation.indexer,
            subgraphDataServiceLegacyAddress,
            true
        );
        afterValues.serviceProvider = _getStorage_ServiceProviderInternal(beforeValues.allocation.indexer);
        afterValues.stakingBalance = token.balanceOf(address(staking));
        afterValues.senderBalance = token.balanceOf(msgSender);
        afterValues.curationBalance = token.balanceOf(address(curation));
        afterValues.beneficiaryBalance = token.balanceOf(rewardsDestination);

        // assert
        assertEq(afterValues.senderBalance + tokens, beforeValues.senderBalance);
        assertEq(afterValues.curationBalance, beforeValues.curationBalance + calcValues.curationCutTokens);
        if (rewardsDestination != address(0)) {
            assertEq(afterValues.beneficiaryBalance, beforeValues.beneficiaryBalance + calcValues.payment);
            assertEq(afterValues.stakingBalance, beforeValues.stakingBalance + calcValues.delegationFeeCut);
        } else {
            assertEq(afterValues.beneficiaryBalance, beforeValues.beneficiaryBalance);
            assertEq(
                afterValues.stakingBalance,
                beforeValues.stakingBalance + calcValues.delegationFeeCut + calcValues.payment
            );
        }

        assertEq(
            afterValues.allocation.collectedFees,
            beforeValues.allocation.collectedFees + tokens - calcValues.protocolTaxTokens - calcValues.curationCutTokens
        );
        assertEq(afterValues.allocation.indexer, beforeValues.allocation.indexer);
        assertEq(afterValues.allocation.subgraphDeploymentID, beforeValues.allocation.subgraphDeploymentID);
        assertEq(afterValues.allocation.tokens, beforeValues.allocation.tokens);
        assertEq(afterValues.allocation.createdAtEpoch, beforeValues.allocation.createdAtEpoch);
        assertEq(afterValues.allocation.closedAtEpoch, beforeValues.allocation.closedAtEpoch);
        assertEq(
            afterValues.allocation.accRewardsPerAllocatedToken,
            beforeValues.allocation.accRewardsPerAllocatedToken
        );
        assertEq(
            afterValues.allocation.distributedRebates,
            beforeValues.allocation.distributedRebates + calcValues.newRebates
        );

        assertEq(afterValues.pool.tokens, beforeValues.pool.tokens + calcValues.delegationFeeCut);
        assertEq(afterValues.pool.shares, beforeValues.pool.shares);
        assertEq(afterValues.pool.tokensThawing, beforeValues.pool.tokensThawing);
        assertEq(afterValues.pool.sharesThawing, beforeValues.pool.sharesThawing);
        assertEq(afterValues.pool.thawingNonce, beforeValues.pool.thawingNonce);

        assertEq(afterValues.serviceProvider.tokensProvisioned, beforeValues.serviceProvider.tokensProvisioned);
        if (rewardsDestination != address(0)) {
            assertEq(afterValues.serviceProvider.tokensStaked, beforeValues.serviceProvider.tokensStaked);
        } else {
            assertEq(
                afterValues.serviceProvider.tokensStaked,
                beforeValues.serviceProvider.tokensStaked + calcValues.payment
            );
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
        address verifier,
        address operator,
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
        // Thawing nonce
        uint256 thawingNonce;
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
            sharesThawing: uint256(vm.load(address(staking), bytes32(baseSlot + 6))),
            thawingNonce: uint256(vm.load(address(staking), bytes32(baseSlot + 7)))
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
        uint32 alphaNumerator_,
        uint32 alphaDenominator_,
        uint32 lambdaNumerator_,
        uint32 lambdaDenominator_
    ) internal {
        // Store alpha numerator and denominator in slot 13
        uint256 alphaSlot = 13;

        uint256 newAlphaSlotValue;
        {
            uint256 alphaNumeratorOffset = 160; // Offset for __DEPRECATED_alphaNumerator (20th byte)
            uint256 alphaDenominatorOffset = 192; // Offset for __DEPRECATED_alphaDenominator (24th byte)

            // Read current value of the slot
            uint256 currentAlphaSlotValue = uint256(vm.load(address(staking), bytes32(alphaSlot)));

            // Create a mask to clear the bits for alphaNumerator and alphaDenominator
            uint256 alphaMask = ~(uint256(0xFFFFFFFF) << alphaNumeratorOffset) &
                ~(uint256(0xFFFFFFFF) << alphaDenominatorOffset);

            // Clear and set new values
            newAlphaSlotValue =
                (currentAlphaSlotValue & alphaMask) |
                (uint256(alphaNumerator_) << alphaNumeratorOffset) |
                (uint256(alphaDenominator_) << alphaDenominatorOffset);
        }

        // Store the updated value back into the slot
        vm.store(address(staking), bytes32(alphaSlot), bytes32(newAlphaSlotValue));

        // Store lambda numerator and denominator in slot 25
        uint256 lambdaSlot = 25;

        uint256 newLambdaSlotValue;
        {
            uint256 lambdaNumeratorOffset = 160; // Offset for lambdaNumerator (20th byte)
            uint256 lambdaDenominatorOffset = 192; // Offset for lambdaDenominator (24th byte)

            // Read current value of the slot
            uint256 currentLambdaSlotValue = uint256(vm.load(address(staking), bytes32(lambdaSlot)));

            // Create a mask to clear the bits for lambdaNumerator and lambdaDenominator
            uint256 lambdaMask = ~(uint256(0xFFFFFFFF) << lambdaNumeratorOffset) &
                ~(uint256(0xFFFFFFFF) << lambdaDenominatorOffset);

            // Clear and set new values
            newLambdaSlotValue =
                (currentLambdaSlotValue & lambdaMask) |
                (uint256(lambdaNumerator_) << lambdaNumeratorOffset) |
                (uint256(lambdaDenominator_) << lambdaDenominatorOffset);
        }

        // Store the updated value back into the slot
        vm.store(address(staking), bytes32(lambdaSlot), bytes32(newLambdaSlotValue));

        // Verify the storage
        (
            uint32 readAlphaNumerator,
            uint32 readAlphaDenominator,
            uint32 readLambdaNumerator,
            uint32 readLambdaDenominator
        ) = _getStorage_RebateParameters();
        assertEq(readAlphaNumerator, alphaNumerator_);
        assertEq(readAlphaDenominator, alphaDenominator_);
        assertEq(readLambdaNumerator, lambdaNumerator_);
        assertEq(readLambdaDenominator, lambdaDenominator_);
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
    // use struct to avoid 'stack too deep' error
    struct CalcValues_ThawRequestData {
        uint256 tokensThawed;
        uint256 tokensThawing;
        uint256 sharesThawed;
        uint256 sharesThawing;
        ThawRequest[] thawRequestsFulfilledList;
        bytes32[] thawRequestsFulfilledListIds;
        uint256[] thawRequestsFulfilledListTokens;
    }

    struct ThawingData {
        uint256 tokensThawed;
        uint256 tokensThawing;
        uint256 sharesThawing;
        uint256 thawRequestsFulfilled;
    }

    struct Params_CalcThawRequestData {
        IHorizonStakingTypes.ThawRequestType thawRequestType;
        address serviceProvider;
        address verifier;
        address owner;
        uint256 iterations;
        bool delegation;
    }

    function calcThawRequestData(Params_CalcThawRequestData memory params) private view returns (CalcValues_ThawRequestData memory) {
        LinkedList.List memory thawRequestList = _getThawRequestList(
            params.thawRequestType,
            params.serviceProvider,
            params.verifier,
            params.owner
        );
        if (thawRequestList.count == 0) {
            return CalcValues_ThawRequestData(0, 0, 0, 0, new ThawRequest[](0), new bytes32[](0), new uint256[](0));
        }

        Provision memory prov = staking.getProvision(params.serviceProvider, params.verifier);
        DelegationPool memory pool = staking.getDelegationPool(params.serviceProvider, params.verifier);

        uint256 tokensThawed = 0;
        uint256 sharesThawed = 0;
        uint256 tokensThawing = params.delegation ? pool.tokensThawing : prov.tokensThawing;
        uint256 sharesThawing = params.delegation ? pool.sharesThawing : prov.sharesThawing;
        uint256 thawRequestsFulfilled = 0;

        bytes32 thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0) && (params.iterations == 0 || thawRequestsFulfilled < params.iterations)) {
            ThawRequest memory thawRequest = _getThawRequest(params.thawRequestType, thawRequestId);
            bool isThawRequestValid = thawRequest.thawingNonce == (params.delegation ? pool.thawingNonce : prov.thawingNonce);
            if (thawRequest.thawingUntil <= block.timestamp) {
                thawRequestsFulfilled++;
                if (isThawRequestValid) {
                    uint256 tokens = params.delegation
                        ? (thawRequest.shares * pool.tokensThawing) / pool.sharesThawing
                        : (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
                    tokensThawed += tokens;
                    tokensThawing -= tokens;
                    sharesThawed += thawRequest.shares;
                    sharesThawing -= thawRequest.shares;
                }
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }

        // we need to do a second pass because solidity doesnt allow dynamic arrays on memory
        CalcValues_ThawRequestData memory thawRequestData;
        thawRequestData.tokensThawed = tokensThawed;
        thawRequestData.tokensThawing = tokensThawing;
        thawRequestData.sharesThawed = sharesThawed;
        thawRequestData.sharesThawing = sharesThawing;
        thawRequestData.thawRequestsFulfilledList = new ThawRequest[](thawRequestsFulfilled);
        thawRequestData.thawRequestsFulfilledListIds = new bytes32[](thawRequestsFulfilled);
        thawRequestData.thawRequestsFulfilledListTokens = new uint256[](thawRequestsFulfilled);
        uint256 i = 0;
        thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0) && (params.iterations == 0 || i < params.iterations)) {
            ThawRequest memory thawRequest = _getThawRequest(params.thawRequestType, thawRequestId);
            bool isThawRequestValid = thawRequest.thawingNonce == (params.delegation ? pool.thawingNonce : prov.thawingNonce);

            if (thawRequest.thawingUntil <= block.timestamp) {
                if (isThawRequestValid) {
                    thawRequestData.thawRequestsFulfilledListTokens[i] = params.delegation
                        ? (thawRequest.shares * pool.tokensThawing) / pool.sharesThawing
                        : (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
                }
                thawRequestData.thawRequestsFulfilledListIds[i] = thawRequestId;
                thawRequestData.thawRequestsFulfilledList[i] = _getThawRequest(params.thawRequestType, thawRequestId);
                thawRequestId = thawRequestData.thawRequestsFulfilledList[i].next;
                i++;
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }

        assertEq(thawRequestsFulfilled, thawRequestData.thawRequestsFulfilledList.length);
        assertEq(thawRequestsFulfilled, thawRequestData.thawRequestsFulfilledListIds.length);
        assertEq(thawRequestsFulfilled, thawRequestData.thawRequestsFulfilledListTokens.length);

        return thawRequestData;
    }

    function _getThawRequestList(
        IHorizonStakingTypes.ThawRequestType thawRequestType,
        address serviceProvider,
        address verifier,
        address owner
    ) private view returns (LinkedList.List memory) {
        return staking.getThawRequestList(
            thawRequestType,
            serviceProvider,
            verifier,
            owner
        );
    }

    function _getThawRequest(
        IHorizonStakingTypes.ThawRequestType thawRequestType,
        bytes32 thawRequestId
    ) private view returns (ThawRequest memory) {
        return staking.getThawRequest(
            thawRequestType,
            thawRequestId
        );
    }
}
