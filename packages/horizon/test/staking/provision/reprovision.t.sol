// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingReprovisionTest is HorizonStakingTest {

    address private newDataService = makeAddr("newDataService");

    function _reprovision(uint256 amount) private {
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, amount);
    }

    function testReprovision_MovingTokens(
        uint64 thawingPeriod,
        uint256 provisionAmount
    )
        public
        useIndexer
        useProvision(provisionAmount, 0, thawingPeriod)
        useThawRequest(provisionAmount)
    {
        skip(thawingPeriod + 1);

        _createProvision(newDataService, MIN_PROVISION_SIZE, 0, thawingPeriod);
        _reprovision(provisionAmount);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, newDataService);
        assertEq(provisionTokens, provisionAmount + MIN_PROVISION_SIZE);
    }

    function testReprovision_OperatorMovingTokens(
        uint64 thawingPeriod,
        uint256 provisionAmount
    )
        public
        useOperator
        useProvision(provisionAmount, 0, thawingPeriod)
        useThawRequest(provisionAmount)
    {
        skip(thawingPeriod + 1);

        // Switch to indexer to set operator for new data service
        vm.startPrank(users.indexer);
        staking.setOperator(users.operator, newDataService, true);
        
        // Switch back to operator
        vm.startPrank(users.operator);
        _createProvision(newDataService, MIN_PROVISION_SIZE, 0, thawingPeriod);
        _reprovision(provisionAmount);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, newDataService);
        assertEq(provisionTokens, provisionAmount + MIN_PROVISION_SIZE);
    }

    function testReprovision_RevertWhen_OperatorNotAuthorizedForNewDataService(
        uint256 provisionAmount
    )
        public
        useOperator
        useProvision(provisionAmount, 0, 0)
        useThawRequest(provisionAmount)
    {
        // Switch to indexer to create new provision
        vm.startPrank(users.indexer);
        _createProvision(newDataService, MIN_PROVISION_SIZE, 0, 0);

        // Switch back to operator
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            newDataService
        );
        vm.expectRevert(expectedError);
        _reprovision(provisionAmount);
    }

    function testReprovision_RevertWhen_NoThawingTokens(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCannotFulfillThawRequest()");
        vm.expectRevert(expectedError);
        _reprovision(amount);
    }

    function testReprovision_RevertWhen_StillThawing(
        uint64 thawingPeriod,
        uint256 provisionAmount
    )
        public
        useIndexer
        useProvision(provisionAmount, 0, thawingPeriod)
        useThawRequest(provisionAmount)
    {
        vm.assume(thawingPeriod > 0);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingStillThawing(uint256)",
            block.timestamp + thawingPeriod
        );
        vm.expectRevert(expectedError);
        _reprovision(provisionAmount);
    }

    function testReprovision_RevertWhen_NotEnoughThawedTokens(
        uint64 thawingPeriod,
        uint256 provisionAmount,
        uint256 newProvisionAmount
    )
        public
        useIndexer
        useProvision(provisionAmount, 0, thawingPeriod)
        useThawRequest(provisionAmount)
    {
        newProvisionAmount = bound(newProvisionAmount, provisionAmount + 1, type(uint256).max - provisionAmount);
        skip(thawingPeriod + 1);

        _createProvision(newDataService, newProvisionAmount, 0, thawingPeriod);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCannotFulfillThawRequest()");
        vm.expectRevert(expectedError);
        _reprovision(newProvisionAmount);
    }
}