// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingReprovisionTest is HorizonStakingTest {

    /*
     * VARIABLES
     */

    address private newDataService = makeAddr("newDataService");

    /*
     * HELPERS
     */

    function _reprovision(uint256 tokens, uint256 nThawRequests) private {
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, tokens, nThawRequests);
    }

    /*
     * TESTS
     */

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

        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);

        // nThawRequests == 0 reprovisions all thaw requests
        _reprovision(provisionAmount, 0);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, newDataService);
        assertEq(provisionTokens, provisionAmount + 1 ether);
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
        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);
        _reprovision(provisionAmount, 0);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, newDataService);
        assertEq(provisionTokens, provisionAmount + 1 ether);
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
        _createProvision(users.indexer, newDataService, 1 ether, 0, 0);

        // Switch back to operator
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            newDataService
        );
        vm.expectRevert(expectedError);
        _reprovision(provisionAmount, 0);
    }

    function testReprovision_RevertWhen_NoThawingTokens(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        _reprovision(amount, 0);
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

        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            provisionAmount,
            0
        );
        vm.expectRevert(expectedError);
        _reprovision(provisionAmount, 0);
    }
}