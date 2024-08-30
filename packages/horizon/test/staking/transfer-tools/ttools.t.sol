// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IL2StakingTypes } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingTypes.sol";
import { IL2StakingBase } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingBase.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";

contract HorizonStakingTransferToolsTest is HorizonStakingTest {
    event Transfer(address indexed from, address indexed to, uint tokens);

    /*
     * TESTS
     */

    function testOnTransfer_RevertWhen_InvalidCaller() public {
        bytes memory data = abi.encode(uint8(0), new bytes(0)); // Valid codes are 0 and 1
        vm.expectRevert(bytes("ONLY_GATEWAY"));
        staking.onTokenTransfer(counterpartStaking, 0, data);
    }

    function testOnTransfer_RevertWhen_InvalidCounterpart() public {
        resetPrank(graphTokenGatewayAddress);

        bytes memory data = abi.encode(uint8(0), new bytes(0)); // Valid codes are 0 and 1
        vm.expectRevert(bytes("ONLY_L1_STAKING_THROUGH_BRIDGE"));
        staking.onTokenTransfer(address(staking), 0, data);
    }

    function testOnTransfer_RevertWhen_InvalidData() public {
        resetPrank(graphTokenGatewayAddress);

        vm.expectRevert();
        staking.onTokenTransfer(counterpartStaking, 0, new bytes(0));
    }

    function testOnTransfer_RevertWhen_InvalidCode() public {
        resetPrank(graphTokenGatewayAddress);

        bytes memory data = abi.encode(uint8(2), new bytes(0)); // Valid codes are 0 and 1
        vm.expectRevert(bytes("INVALID_CODE"));
        staking.onTokenTransfer(counterpartStaking, 0, data);
    }

    function testOnTransfer_RevertWhen_ProvisionNotFound(uint256 amount) public {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);

        resetPrank(graphTokenGatewayAddress);
        bytes memory data = abi.encode(
            uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE),
            abi.encode(users.indexer, users.delegator)
        );
        vm.expectRevert(bytes("!provision"));
        staking.onTokenTransfer(counterpartStaking, amount, data);
    }

    function testOnTransfer_ReceiveDelegation_RevertWhen_InvalidData() public {
        resetPrank(graphTokenGatewayAddress);

        bytes memory data = abi.encode(uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE), new bytes(0));
        vm.expectRevert();
        staking.onTokenTransfer(counterpartStaking, 0, data);
    }

    function testOnTransfer_ReceiveDelegation(uint256 amount) public {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);

        // create provision and legacy delegation pool - this is done by the bridge when indexers move to L2
        resetPrank(users.indexer);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, 100 ether, 0, 0);

        resetPrank(users.delegator);
        _delegate(users.indexer, 1 ether);

        // send amount to staking contract - this should be done by the bridge
        resetPrank(users.delegator);
        token.transfer(address(staking), amount);

        resetPrank(graphTokenGatewayAddress);
        bytes memory data = abi.encode(
            uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE),
            abi.encode(users.indexer, users.delegator)
        );
        _onTokenTransfer_ReceiveDelegation(counterpartStaking, amount, data);
    }

    function testOnTransfer_ReceiveDelegation_WhenThawing(uint256 amount) public {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);
        uint256 originalDelegationAmount = 10 ether;

        // create provision and legacy delegation pool - this is done by the bridge when indexers move to L2
        resetPrank(users.indexer);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, 100 ether, 0, 1 days);

        resetPrank(users.delegator);
        _delegate(users.indexer, originalDelegationAmount);

        // send amount to staking contract - this should be done by the bridge
        resetPrank(users.delegator);
        token.transfer(address(staking), amount);

        // thaw some delegation before receiving new delegation from L1
        resetPrank(users.delegator);
        _undelegate(users.indexer, originalDelegationAmount / 10);

        resetPrank(graphTokenGatewayAddress);
        bytes memory data = abi.encode(
            uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE),
            abi.encode(users.indexer, users.delegator)
        );
        _onTokenTransfer_ReceiveDelegation(counterpartStaking, amount, data);
    }

    function testOnTransfer_ReceiveDelegation_WhenInvalidPool(uint256 amount) public useDelegationSlashing() {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);
        uint256 originalDelegationAmount = 10 ether;
        uint256 provisionSize = 100 ether;

        // create provision and legacy delegation pool - this is done by the bridge when indexers move to L2
        resetPrank(users.indexer);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, provisionSize, 0, 1 days);

        // initialize the delegation pool
        resetPrank(users.delegator);
        _delegate(users.indexer, originalDelegationAmount);

        // slash the entire provision
        resetPrank(subgraphDataServiceLegacyAddress);
        _slash(users.indexer, subgraphDataServiceLegacyAddress, provisionSize + originalDelegationAmount, 0);

        // send amount to staking contract - this should be done by the bridge
        resetPrank(users.delegator);
        token.transfer(address(staking), amount);

        resetPrank(graphTokenGatewayAddress);
        bytes memory data = abi.encode(
            uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE),
            abi.encode(users.indexer, users.delegator)
        );
        _onTokenTransfer_ReceiveDelegation(counterpartStaking, amount, data);
    }
    function testOnTransfer_ReceiveDelegation_WhenAllThawing(uint256 amountReceived, uint256 amountDelegated) public {
        amountReceived = bound(amountReceived, 1 ether, MAX_STAKING_TOKENS);
        amountDelegated = bound(amountDelegated, 1 ether, MAX_STAKING_TOKENS);

        // create provision and legacy delegation pool - this is done by the bridge when indexers move to L2
        resetPrank(users.indexer);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, 100 ether, 0, 1 days);

        resetPrank(users.delegator);
        _delegate(users.indexer, amountDelegated);

        // send amount to staking contract - this should be done by the bridge
        resetPrank(users.delegator);
        token.transfer(address(staking), amountReceived);

        // thaw all delegation before receiving new delegation from L1
        resetPrank(users.delegator);
        _undelegate(users.indexer, amountDelegated);

        resetPrank(graphTokenGatewayAddress);
        bytes memory data = abi.encode(
            uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE),
            abi.encode(users.indexer, users.delegator)
        );
        _onTokenTransfer_ReceiveDelegation(counterpartStaking, amountReceived, data);
    }

    /**
     * HELPERS
     */

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
}
