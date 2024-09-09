// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IL2StakingTypes } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingTypes.sol";

contract HorizonStakingTransferToolsTest is HorizonStakingTest {
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
}
