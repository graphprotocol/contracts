// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IL2StakingTypes } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingTypes.sol";

contract HorizonStakingTransferToolsTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testOnTransfer_RevertWhen_InvalidCaller(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {

      bytes memory data = abi.encode(uint8(0), new bytes(0)); // Valid codes are 0 and 1
      vm.expectRevert(bytes("ONLY_GATEWAY"));
      staking.onTokenTransfer(counterpartStaking, 0, data);
    }

    function testOnTransfer_RevertWhen_InvalidCounterpart(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
      resetPrank(graphTokenGatewayAddress);

      bytes memory data = abi.encode(uint8(0), new bytes(0)); // Valid codes are 0 and 1
      vm.expectRevert(bytes("ONLY_L1_STAKING_THROUGH_BRIDGE"));
      staking.onTokenTransfer(address(staking), 0, data);
    }

    function testOnTransfer_RevertWhen_InvalidData(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
      resetPrank(graphTokenGatewayAddress);

      vm.expectRevert();
      staking.onTokenTransfer(counterpartStaking, 0, new bytes(0));
    }

    function testOnTransfer_RevertWhen_InvalidCode(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
      resetPrank(graphTokenGatewayAddress);

      bytes memory data = abi.encode(uint8(2), new bytes(0)); // Valid codes are 0 and 1
      vm.expectRevert(bytes("INVALID_CODE"));
      staking.onTokenTransfer(counterpartStaking, 0, data);
    }

    function testOnTransfer_ReceiveDelegation_RevertWhen_InvalidData(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
      resetPrank(graphTokenGatewayAddress);

      bytes memory data = abi.encode(uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE), new bytes(0));
      vm.expectRevert();
      staking.onTokenTransfer(counterpartStaking, 0, data);
    }

    function testOnTransfer_ReceiveDelegation(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
      resetPrank(graphTokenGatewayAddress);

      bytes memory data = abi.encode(uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE), abi.encode(users.indexer, users.delegator));
      staking.onTokenTransfer(counterpartStaking, 0, data);
    }
}
