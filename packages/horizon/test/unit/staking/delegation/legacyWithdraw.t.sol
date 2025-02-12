// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "../../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { IHorizonStakingExtension } from "../../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";
import { LinkedList } from "../../../../contracts/libraries/LinkedList.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingLegacyWithdrawDelegationTest is HorizonStakingTest {
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

    function _legacyWithdrawDelegated(address _indexer) internal {
        (, address delegator, ) = vm.readCallers();
        IHorizonStakingTypes.DelegationPool memory pool = staking.getDelegationPool(
            _indexer,
            subgraphDataServiceLegacyAddress
        );
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeDelegatorBalance = token.balanceOf(users.delegator);

        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.StakeDelegatedWithdrawn(_indexer, delegator, pool.tokens);
        staking.withdrawDelegated(users.indexer, address(0));

        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterDelegatorBalance = token.balanceOf(users.delegator);

        assertEq(afterStakingBalance, beforeStakingBalance - pool.tokens);
        assertEq(afterDelegatorBalance - pool.tokens, beforeDelegatorBalance);

        DelegationInternal memory delegation = _getStorage_Delegation(
            _indexer,
            subgraphDataServiceLegacyAddress,
            delegator,
            true
        );
        assertEq(delegation.shares, 0);
        assertEq(delegation.__DEPRECATED_tokensLocked, 0);
        assertEq(delegation.__DEPRECATED_tokensLockedUntil, 0);
    }

    /*
     * TESTS
     */

    function testWithdraw_Legacy(uint256 tokensLocked) public useDelegator {
        vm.assume(tokensLocked > 0);

        _setStorage_DelegationPool(users.indexer, tokensLocked, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, tokensLocked, 1);
        token.transfer(address(staking), tokensLocked);

        _legacyWithdrawDelegated(users.indexer);
    }

    function testWithdraw_Legacy_RevertWhen_NoTokens() public useDelegator {
        _setStorage_DelegationPool(users.indexer, 0, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, 0, 0);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingToWithdraw()");
        vm.expectRevert(expectedError);
        staking.withdrawDelegated(users.indexer, address(0));
    }
}
