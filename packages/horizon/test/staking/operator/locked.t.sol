// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingOperatorLockedTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testOperatorLocked_Set() public useIndexer useLockedVerifier(subgraphDataServiceAddress) {
        staking.setOperatorLocked(users.operator, subgraphDataServiceAddress, true);
        assertTrue(staking.isAuthorized(users.operator, users.indexer, subgraphDataServiceAddress));
    }

    function testOperatorLocked_RevertWhen_VerifierNotAllowed() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingVerifierNotAllowed(address)", subgraphDataServiceAddress);
        vm.expectRevert(expectedError);
        staking.setOperatorLocked(users.operator, subgraphDataServiceAddress, true);
    }

    function testOperatorLocked_RevertWhen_CallerIsServiceProvider() public useIndexer useLockedVerifier(subgraphDataServiceAddress) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCallerIsServiceProvider()");
        vm.expectRevert(expectedError);
        staking.setOperatorLocked(users.indexer, subgraphDataServiceAddress, true);
    }

    function testOperatorLocked_SetLegacySubgraphService() public useIndexer useLockedVerifier(subgraphDataServiceLegacyAddress) {
        staking.setOperatorLocked(users.operator, subgraphDataServiceLegacyAddress, true);
        assertTrue(staking.isAuthorized(users.operator, users.indexer, subgraphDataServiceLegacyAddress));
    }
}