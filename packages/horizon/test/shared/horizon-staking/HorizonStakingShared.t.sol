// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IHorizonStaking } from "../../../contracts/interfaces/IHorizonStaking.sol";
import { IHorizonStakingBase } from "../../../contracts/interfaces/internal/IHorizonStakingBase.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";
import { MathUtils } from "../../../contracts/libraries/MathUtils.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {
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
        IHorizonStaking.ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            serviceProvider
        );

        // stakeTo
        token.approve(address(staking), tokens);
        vm.expectEmit();
        emit IHorizonStakingBase.StakeDeposited(serviceProvider, tokens);
        staking.stakeTo(serviceProvider, tokens);

        // after
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        IHorizonStaking.ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            serviceProvider
        );

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
        IHorizonStaking.ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            msgSender
        );

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
        IHorizonStaking.ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            msgSender
        );

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
        IHorizonStaking.ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            msgSender
        );
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        // withdraw
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.StakeWithdrawn(msgSender, beforeServiceProvider.__DEPRECATED_tokensLocked);
        staking.withdraw();

        // after
        IHorizonStaking.ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            msgSender
        );
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
        IHorizonStaking.ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            serviceProvider
        );

        // provision
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionCreated(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
        staking.provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);

        // after
        IHorizonStaking.Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        IHorizonStaking.ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            serviceProvider
        );

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
        IHorizonStaking.Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        IHorizonStaking.ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(
            serviceProvider
        );

        // addToProvision
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionIncreased(serviceProvider, verifier, tokens);
        staking.addToProvision(serviceProvider, verifier, tokens);

        // after
        IHorizonStaking.Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        IHorizonStaking.ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(
            serviceProvider
        );

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
        IHorizonStaking.Provision memory beforeProvision = staking.getProvision(serviceProvider, verifier);
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );
        IHorizonStaking.ThawRequest memory beforeTailThawRequest = staking.getThawRequest(beforeThawRequestList.tail);

        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(users.indexer, subgraphDataServiceAddress, users.indexer, uint256(0))
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
        IHorizonStaking.Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        IHorizonStaking.ThawRequest memory afterThawRequest = staking.getThawRequest(thawRequestId);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(
            serviceProvider,
            verifier,
            serviceProvider
        );

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
        if (beforeThawRequestList.count != 0) {
            assertEq(beforeTailThawRequest.next, thawRequestId);
        }

        return thawRequestId;
    }

    function _deprovision(uint256 nThawRequests) internal {
        staking.deprovision(users.indexer, subgraphDataServiceAddress, nThawRequests);
    }

    /*
     * STORAGE HELPERS
     */
    function _getStorage_ServiceProviderInternal(
        address serviceProvider
    ) internal view returns (IHorizonStaking.ServiceProviderInternal memory) {
        uint256 slotNumber = 14;
        uint256 baseSlotUint = uint256(keccak256(abi.encode(serviceProvider, slotNumber)));

        IHorizonStakingTypes.ServiceProviderInternal memory serviceProviderInternal = IHorizonStakingTypes
            .ServiceProviderInternal({
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
}
