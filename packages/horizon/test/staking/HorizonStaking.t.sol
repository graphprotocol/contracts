// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingTypes } from "../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingTest is HorizonStakingSharedTest, IHorizonStakingTypes {

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
        (, msgSender,) = vm.readCallers();
        vm.assume(delegationAmount > MIN_DELEGATION);
        vm.assume(delegationAmount <= MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceAddress);
        vm.startPrank(msgSender);
        _;
    }

    modifier useLockedVerifier(address verifier) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(users.governor);
        staking.setAllowedLockedVerifier(verifier, true);
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

    function _delegate(uint256 amount, address verifier) internal {
        token.approve(address(staking), amount);
        staking.delegate(users.indexer, verifier, amount, 0);
    }

    function _getDelegation(address verifier) internal view returns (Delegation memory) {
        return staking.getDelegation(users.indexer, verifier, users.delegator);
    }

    function _undelegate(uint256 shares, address verifier) internal {
        staking.undelegate(users.indexer, verifier, shares);
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
}
