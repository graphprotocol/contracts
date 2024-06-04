// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingProvisionLockedTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testProvisionLocked_Create(
        uint256 amount
    ) public useIndexer useStake(amount) useLockedVerifier(subgraphDataServiceAddress) {
        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, 0);

        staking.setOperatorLocked(users.operator, subgraphDataServiceAddress, true);

        vm.startPrank(users.operator);
        staking.provisionLocked(
            users.indexer,
            subgraphDataServiceAddress,
            amount,
            MAX_MAX_VERIFIER_CUT,
            MAX_THAWING_PERIOD
        );

        provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, amount);
    }

    function testProvisionLocked_RevertWhen_VerifierNotAllowed(
        uint256 amount
    ) public useIndexer useStake(amount) useLockedVerifier(subgraphDataServiceAddress) {
        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, 0);

        // Set operator
        staking.setOperatorLocked(users.operator, subgraphDataServiceAddress, true);

        // Disable locked verifier
        vm.startPrank(users.governor);
        staking.setAllowedLockedVerifier(subgraphDataServiceAddress, false);

        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingVerifierNotAllowed(address)", subgraphDataServiceAddress);
        vm.expectRevert(expectedError);
        staking.provisionLocked(
            users.indexer,
            subgraphDataServiceAddress,
            amount,
            MAX_MAX_VERIFIER_CUT,
            MAX_THAWING_PERIOD
        );
    }

    function testProvisionLocked_RevertWhen_OperatorNotAllowed(
        uint256 amount
    ) public useIndexer useStake(amount) useLockedVerifier(subgraphDataServiceAddress) {
        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, 0);

        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.provisionLocked(
            users.indexer,
            subgraphDataServiceAddress,
            amount,
            MAX_MAX_VERIFIER_CUT,
            MAX_THAWING_PERIOD
        );
    }
}