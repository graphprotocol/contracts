// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingTypes } from "../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingTest is HorizonStakingSharedTest, IHorizonStakingTypes {

    modifier useOperator() {
        vm.startPrank(users.indexer);
        staking.setOperator(users.operator, subgraphDataServiceAddress, true);
        vm.startPrank(users.operator);
        _;
        vm.stopPrank();
    }

    modifier useStake(uint256 amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        approve(address(staking), amount);
        staking.stake(amount);
        _;
    }

    modifier useStakeTo(address to, uint256 amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
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
        _deprovision(amount);
        _;
    }

    modifier useDelegation(uint256 delegationAmount) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        vm.assume(delegationAmount > MIN_DELEGATION);
        vm.assume(delegationAmount <= 10_000_000_000 ether);
        vm.startPrank(users.delegator);
        _delegate(delegationAmount);
        vm.startPrank(msgSender);
        _;
    }

    function _stakeTo(address to, uint256 amount) internal {
        approve(address(staking), amount);
        staking.stakeTo(to, amount);
    }

    function _createThawRequest(uint256 thawAmount) internal returns (bytes32) {
        return staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function _deprovision(uint256 amount) internal {
        staking.deprovision(users.indexer, subgraphDataServiceAddress, amount);
    }

    function _delegate(uint256 amount) internal {
        token.approve(address(staking), amount);
        staking.delegate(users.indexer, subgraphDataServiceAddress, amount, 0);
    }

    function _getDelegation() internal view returns (Delegation memory) {
        return staking.getDelegation(users.indexer, subgraphDataServiceAddress, users.delegator);
    }

    function _undelegate(uint256 shares) internal {
        staking.undelegate(users.indexer, subgraphDataServiceAddress, shares);
    }

    function _getDelegationPool() internal view returns (DelegationPool memory) {
        return staking.getDelegationPool(users.indexer, subgraphDataServiceAddress);
    }
}