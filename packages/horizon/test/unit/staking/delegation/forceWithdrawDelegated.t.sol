// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingForceWithdrawDelegatedTest is HorizonStakingTest {
    /*
     * MODIFIERS
     */

    modifier useDelegator() {
        resetPrank(users.delegator);
        _;
    }

    /*
     * HELPERS
     */

    function _setLegacyDelegation(
        address _indexer,
        address _delegator,
        uint256 _shares,
        uint256 __DEPRECATED_tokensLocked,
        uint256 __DEPRECATED_tokensLockedUntil
    ) public {
        // Calculate the base storage slot for the serviceProvider in the mapping
        bytes32 baseSlot = keccak256(abi.encode(_indexer, uint256(20)));

        // Calculate the slot for the delegator's DelegationInternal struct
        bytes32 delegatorSlot = keccak256(abi.encode(_delegator, bytes32(uint256(baseSlot) + 4)));

        // Use vm.store to set each field of the struct
        vm.store(address(staking), bytes32(uint256(delegatorSlot)), bytes32(_shares));
        vm.store(address(staking), bytes32(uint256(delegatorSlot) + 1), bytes32(__DEPRECATED_tokensLocked));
        vm.store(address(staking), bytes32(uint256(delegatorSlot) + 2), bytes32(__DEPRECATED_tokensLockedUntil));
    }

    /*
     * ACTIONS
     */

    function _forceWithdrawDelegated(address _indexer, address _delegator) internal {
        IHorizonStakingTypes.DelegationPool memory pool = staking.getDelegationPool(
            _indexer,
            subgraphDataServiceLegacyAddress
        );
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeDelegatorBalance = token.balanceOf(_delegator);

        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.StakeDelegatedWithdrawn(_indexer, _delegator, pool.tokens);
        staking.forceWithdrawDelegated(_indexer, _delegator);

        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterDelegatorBalance = token.balanceOf(_delegator);

        assertEq(afterStakingBalance, beforeStakingBalance - pool.tokens);
        assertEq(afterDelegatorBalance - pool.tokens, beforeDelegatorBalance);

        DelegationInternal memory delegation = _getStorage_Delegation(
            _indexer,
            subgraphDataServiceLegacyAddress,
            _delegator,
            true
        );
        assertEq(delegation.shares, 0);
        assertEq(delegation.__DEPRECATED_tokensLocked, 0);
        assertEq(delegation.__DEPRECATED_tokensLockedUntil, 0);
    }

    /*
     * TESTS
     */

    function testForceWithdrawDelegated_Tokens(uint256 tokensLocked) public useDelegator {
        vm.assume(tokensLocked > 0);

        _setStorage_DelegationPool(users.indexer, tokensLocked, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, tokensLocked, 1);
        token.transfer(address(staking), tokensLocked);

        // switch to a third party (not the delegator)
        resetPrank(users.operator);

        _forceWithdrawDelegated(users.indexer, users.delegator);
    }

    function testForceWithdrawDelegated_CalledByDelegator(uint256 tokensLocked) public useDelegator {
        vm.assume(tokensLocked > 0);

        _setStorage_DelegationPool(users.indexer, tokensLocked, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, tokensLocked, 1);
        token.transfer(address(staking), tokensLocked);

        // delegator can also call forceWithdrawDelegated on themselves
        _forceWithdrawDelegated(users.indexer, users.delegator);
    }

    function testForceWithdrawDelegated_RevertWhen_NoTokens() public useDelegator {
        _setStorage_DelegationPool(users.indexer, 0, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, 0, 0);

        // switch to a third party
        resetPrank(users.operator);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingToWithdraw()");
        vm.expectRevert(expectedError);
        staking.forceWithdrawDelegated(users.indexer, users.delegator);
    }

    function testForceWithdrawDelegated_RevertWhen_StillLocked(uint256 tokensLocked) public useDelegator {
        vm.assume(tokensLocked > 0);

        // Set a future epoch for tokensLockedUntil
        uint256 futureEpoch = 1000;
        _setStorage_DelegationPool(users.indexer, tokensLocked, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, tokensLocked, futureEpoch);
        token.transfer(address(staking), tokensLocked);

        // switch to a third party
        resetPrank(users.operator);

        // Should revert because tokens are still locked (current epoch < futureEpoch)
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingToWithdraw()");
        vm.expectRevert(expectedError);
        staking.forceWithdrawDelegated(users.indexer, users.delegator);
    }
}
