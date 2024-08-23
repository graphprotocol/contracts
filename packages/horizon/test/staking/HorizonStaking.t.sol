// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { LinkedList } from "../../contracts/libraries/LinkedList.sol";
import { MathUtils } from "../../contracts/libraries/MathUtils.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingTest is HorizonStakingSharedTest, IHorizonStakingTypes {
    using stdStorage for StdStorage;

    /*
     * MODIFIERS
     */

    modifier usePausedStaking() {
        vm.startPrank(users.governor);
        controller.setPaused(true);
        vm.stopPrank();
        _;
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
        approve(address(staking), amount);
        staking.stake(amount);
        _;
    }

    modifier useStakeTo(address to, uint256 amount) {
        vm.assume(amount > 0);
        _stakeTo(to, amount);
        _;
    }

    modifier useThawRequest(uint256 thawAmount) {
        vm.assume(thawAmount > 0);
        _createThawRequest(thawAmount);
        _;
    }

    modifier useThawAndDeprovision(uint256 amount, uint64 thawingPeriod) {
        vm.assume(amount > 0);
        _createThawRequest(amount);
        skip(thawingPeriod + 1);
        _deprovision(0);
        _;
    }

    modifier useDelegation(uint256 delegationAmount) {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        vm.assume(delegationAmount > MIN_DELEGATION);
        vm.assume(delegationAmount <= MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
        vm.startPrank(msgSender);
        _;
    }

    modifier useLockedVerifier(address verifier) {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(users.governor);
        staking.setAllowedLockedVerifier(verifier, true);
        resetPrank(msgSender);
        _;
    }

    modifier useDelegationSlashing() {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(users.governor);
        staking.setDelegationSlashingEnabled();
        resetPrank(msgSender);
        _;
    }

    /*
     * HELPERS
     */

    function _stakeTo(address to, uint256 amount) internal {
        approve(address(staking), amount);
        staking.stakeTo(to, amount);
    }

    function _createThawRequest(uint256 thawAmount) internal returns (bytes32) {
        return staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function _deprovision(uint256 nThawRequests) internal {
        staking.deprovision(users.indexer, subgraphDataServiceAddress, nThawRequests);
    }

    function _delegate(address serviceProvider, address verifier, uint256 tokens, uint256 minSharesOut) internal {
        __delegate(serviceProvider, verifier, tokens, minSharesOut, false);
    }

    function _delegateLegacy(address serviceProvider, uint256 tokens) internal {
        __delegate(serviceProvider, subgraphDataServiceLegacyAddress, tokens, 0, true);
    }


    struct DelegateData {
        DelegationPool pool;
        Delegation delegation;
        uint256 storagePoolTokens;
        uint256 delegatedTokens;
        uint256 delegatorBalance;
        uint256 stakingBalance;
    }

    function __delegate(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint256 minSharesOut,
        bool legacy
    ) internal {
        (, address delegator, ) = vm.readCallers();

        // before
        DelegateData memory beforeData = DelegateData({
            pool: staking.getDelegationPool(serviceProvider, verifier),
            delegation: staking.getDelegation(serviceProvider, verifier, delegator),
            storagePoolTokens: uint256(vm.load(address(staking), _getSlotPoolTokens(serviceProvider, verifier, legacy))),
            delegatedTokens: staking.getDelegatedTokensAvailable(serviceProvider, verifier),
            delegatorBalance: token.balanceOf(delegator),
            stakingBalance: token.balanceOf(address(staking))
        });

        uint256 calcShares = (beforeData.pool.tokens == 0 || beforeData.pool.tokens == beforeData.pool.tokensThawing)
            ? tokens
            : ((tokens * beforeData.pool.shares) / (beforeData.pool.tokens - beforeData.pool.tokensThawing));

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
        DelegateData memory afterData = DelegateData({
            pool: staking.getDelegationPool(serviceProvider, verifier),
            delegation: staking.getDelegation(serviceProvider, verifier, delegator),
            storagePoolTokens: uint256(vm.load(address(staking), _getSlotPoolTokens(serviceProvider, verifier, legacy))),
            delegatedTokens: staking.getDelegatedTokensAvailable(serviceProvider, verifier),
            delegatorBalance: token.balanceOf(delegator),
            stakingBalance: token.balanceOf(address(staking))
        });

        uint256 deltaShares = afterData.delegation.shares - beforeData.delegation.shares;

        // assertions
        assertEq(beforeData.pool.tokens + tokens, afterData.pool.tokens);
        assertEq(beforeData.pool.shares + calcShares, afterData.pool.shares);
        assertEq(beforeData.pool.tokensThawing, afterData.pool.tokensThawing);
        assertEq(beforeData.pool.sharesThawing, afterData.pool.sharesThawing);
        assertGe(deltaShares, minSharesOut);
        assertEq(calcShares, deltaShares);
        assertEq(beforeData.delegatedTokens + tokens, afterData.delegatedTokens);
        // Ensure correct slot is being updated, pools are stored in different storage locations for legacy subgraph data service
        assertEq(beforeData.storagePoolTokens + tokens, afterData.storagePoolTokens);
        assertEq(beforeData.delegatorBalance - tokens, afterData.delegatorBalance);
        assertEq(beforeData.stakingBalance + tokens, afterData.stakingBalance);
    }

    function _undelegate(address serviceProvider, address verifier, uint256 shares) internal {
        __undelegate(serviceProvider, verifier, shares, false);
    }

    function _undelegateLegacy(address serviceProvider, uint256 shares) internal {
        __undelegate(serviceProvider, subgraphDataServiceLegacyAddress, shares, true);
    }

    function __undelegate(address serviceProvider, address verifier, uint256 shares, bool legacy) internal {
        (, address delegator, ) = vm.readCallers();

        // Delegation pool data is stored in a different storage slot for the legacy subgraph data service
        bytes32 slotPoolShares;
        if (legacy) {
            slotPoolShares = bytes32(uint256(keccak256(abi.encode(serviceProvider, 20))) + 3);
        } else {
            slotPoolShares = bytes32(
                uint256(keccak256(abi.encode(verifier, keccak256(abi.encode(serviceProvider, 33))))) + 3
            );
        }

        // before
        DelegationPool memory beforePool = staking.getDelegationPool(serviceProvider, verifier);
        Delegation memory beforeDelegation = staking.getDelegation(serviceProvider, verifier, delegator);
        LinkedList.List memory beforeThawRequestList = staking.getThawRequestList(serviceProvider, verifier, delegator);
        uint256 beforeStoragePoolShares = uint256(vm.load(address(staking), slotPoolShares));
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
        DelegationPool memory afterPool = staking.getDelegationPool(users.indexer, verifier);
        Delegation memory afterDelegation = staking.getDelegation(serviceProvider, verifier, delegator);
        LinkedList.List memory afterThawRequestList = staking.getThawRequestList(serviceProvider, verifier, delegator);
        ThawRequest memory afterThawRequest = staking.getThawRequest(calcThawRequestId);
        uint256 afterStoragePoolShares = uint256(vm.load(address(staking), slotPoolShares));
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
        // Ensure correct slot is being updated, pools are stored in different storage locations for legacy subgraph data service
        assertEq(beforeStoragePoolShares, afterStoragePoolShares + shares);
    }

    // todo remove these
    function _getDelegation(address verifier) internal view returns (Delegation memory) {
        return staking.getDelegation(users.indexer, verifier, users.delegator);
    }

    function _getDelegationPool(address verifier) internal view returns (DelegationPool memory) {
        return staking.getDelegationPool(users.indexer, verifier);
    }

    function _storeServiceProvider(
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

    function _slash(address serviceProvider, address verifier, uint256 tokens, uint256 verifierCutAmount) internal {
        uint256 beforeProviderTokens = staking.getProviderTokensAvailable(serviceProvider, verifier);
        uint256 beforeDelegationTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);
        bool isDelegationSlashingEnabled = staking.isDelegationSlashingEnabled();

        // Calculate expected tokens after slashing
        uint256 providerTokensSlashed = MathUtils.min(beforeProviderTokens, tokens);
        uint256 expectedProviderTokensAfterSlashing = beforeProviderTokens - providerTokensSlashed;

        uint256 delegationTokensSlashed = MathUtils.min(beforeDelegationTokens, tokens - providerTokensSlashed);
        uint256 expectedDelegationTokensAfterSlashing = beforeDelegationTokens -
            (isDelegationSlashingEnabled ? delegationTokensSlashed : 0);

        vm.expectEmit(address(staking));
        if (verifierCutAmount > 0) {
            emit IHorizonStakingMain.VerifierTokensSent(
                serviceProvider,
                verifier,
                verifier,
                verifierCutAmount
            );
        }
        emit IHorizonStakingMain.ProvisionSlashed(serviceProvider, verifier, providerTokensSlashed);

        if (isDelegationSlashingEnabled) {
            emit IHorizonStakingMain.DelegationSlashed(
                serviceProvider,
                verifier,
                delegationTokensSlashed
            );
        } else {
            emit IHorizonStakingMain.DelegationSlashingSkipped(
                serviceProvider,
                verifier,
                delegationTokensSlashed
            );
        }
        staking.slash(serviceProvider, tokens, verifierCutAmount, verifier);

        if (!isDelegationSlashingEnabled) {
            expectedDelegationTokensAfterSlashing = beforeDelegationTokens;
        }

        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, verifier);
        assertEq(provisionTokens, expectedProviderTokensAfterSlashing);

        uint256 delegationTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);
        assertEq(delegationTokens, expectedDelegationTokensAfterSlashing);

        uint256 verifierTokens = token.balanceOf(verifier);
        assertEq(verifierTokens, verifierCutAmount);
    }

    function _getSlotPoolTokens(address serviceProvider, address verifier, bool legacy) private returns (bytes32) {
        bytes32 slotPoolTokens;
        if (legacy) {
            slotPoolTokens = bytes32(uint256(keccak256(abi.encode(serviceProvider, 20))) + 2);
        } else {
            slotPoolTokens = bytes32(
                uint256(keccak256(abi.encode(verifier, keccak256(abi.encode(serviceProvider, 33))))) + 2
            );
        }
        return slotPoolTokens;
    } 
}
