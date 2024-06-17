// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

contract HorizonStakingProvisionParametersTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function test_ProvisionParametersSet(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, 0, 0) {
        vm.assume(maxVerifierCut != 0);
        vm.assume(thawingPeriod != 0);
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionParametersStaged(
            users.indexer,
            subgraphDataServiceAddress,
            maxVerifierCut,
            thawingPeriod
        );
        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);

        Provision memory prov = staking.getProvision(users.indexer, subgraphDataServiceAddress);
        assertEq(prov.maxVerifierCutPending, maxVerifierCut);
        assertEq(prov.thawingPeriodPending, thawingPeriod);
    }

    function test_ProvisionParametersSet_RevertWhen_ProvisionNotExists(
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer {
        vm.expectRevert(
            abi.encodeWithSignature(
                "HorizonStakingInvalidProvision(address,address)",
                users.indexer,
                subgraphDataServiceAddress
            )
        );
        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);
    }

    function test_ProvisionParametersSet_RevertWhen_CallerNotAuthorized(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.startPrank(msg.sender); // stop impersonating the indexer
        vm.expectRevert(
            abi.encodeWithSignature(
                "HorizonStakingNotAuthorized(address,address,address)",
                msg.sender,
                users.indexer,
                subgraphDataServiceAddress
            )
        );
        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);
        vm.stopPrank();
    }

    function test_ProvisionParametersSet_RevertWhen_ProtocolPaused(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) usePausedStaking {
        vm.expectRevert(abi.encodeWithSignature("ManagedIsPaused()"));
        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);
    }

    function test_ProvisionParametersAccept(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        Provision memory prov = staking.getProvision(users.indexer, subgraphDataServiceAddress);

        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);

        vm.startPrank(subgraphDataServiceAddress);

        if (maxVerifierCut != prov.maxVerifierCut || thawingPeriod != prov.thawingPeriod) {
            vm.expectEmit();
            emit IHorizonStakingMain.ProvisionParametersSet(
                users.indexer,
                subgraphDataServiceAddress,
                maxVerifierCut,
                thawingPeriod
            );
        }
        staking.acceptProvisionParameters(users.indexer);
        vm.stopPrank();

        assertEq(prov.maxVerifierCut, maxVerifierCut);
        assertEq(prov.maxVerifierCutPending, maxVerifierCut);
        assertEq(prov.thawingPeriod, thawingPeriod);
        assertEq(prov.thawingPeriodPending, thawingPeriod);
    }
}
