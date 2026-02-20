// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

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
        uint256 _deprecatedTokensLocked,
        uint256 _deprecatedTokensLockedUntil
    ) public {
        // Calculate the base storage slot for the serviceProvider in the mapping
        bytes32 baseSlot = keccak256(abi.encode(_indexer, uint256(20)));

        // Calculate the slot for the delegator's DelegationInternal struct
        bytes32 delegatorSlot = keccak256(abi.encode(_delegator, bytes32(uint256(baseSlot) + 4)));

        // Use vm.store to set each field of the struct
        vm.store(address(staking), bytes32(uint256(delegatorSlot)), bytes32(_shares));
        vm.store(address(staking), bytes32(uint256(delegatorSlot) + 1), bytes32(_deprecatedTokensLocked));
        vm.store(address(staking), bytes32(uint256(delegatorSlot) + 2), bytes32(_deprecatedTokensLockedUntil));
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

        DelegationInternal memory delegation = _getStorageDelegation(
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

        _setStorageDelegationPool(users.indexer, tokensLocked, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, tokensLocked, 1);
        require(token.transfer(address(staking), tokensLocked), "Transfer failed");

        _legacyWithdrawDelegated(users.indexer);
    }

    function testWithdraw_Legacy_RevertWhen_NoTokens() public useDelegator {
        _setStorageDelegationPool(users.indexer, 0, 0, 0);
        _setLegacyDelegation(users.indexer, users.delegator, 0, 0, 0);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingToWithdraw()");
        vm.expectRevert(expectedError);
        staking.withdrawDelegated(users.indexer, address(0));
    }
}
