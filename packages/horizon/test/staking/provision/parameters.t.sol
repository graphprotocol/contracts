// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

contract HorizonStakingProvisionParametersTest is HorizonStakingTest {

    /*
     * MODIFIERS
     */

    modifier useValidParameters(uint32 maxVerifierCut, uint64 thawingPeriod) {
        vm.assume(maxVerifierCut <= MAX_PPM);
        vm.assume(thawingPeriod <= MAX_THAWING_PERIOD);
        _;
    }

    /*
     * TESTS
     */

    function test_ProvisionParametersSet(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, 0, 0) useValidParameters(maxVerifierCut, thawingPeriod) {
        _setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);
    }

    function test_ProvisionParametersSet_RevertWhen_ProvisionNotExists(
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useValidParameters(maxVerifierCut, thawingPeriod) {
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
        _setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);

        vm.startPrank(subgraphDataServiceAddress);
        _acceptProvisionParameters(users.indexer);
        vm.stopPrank();
    }

    function test_ProvisionParameters_RevertWhen_InvalidMaxVerifierCut(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        maxVerifierCut = uint32(bound(maxVerifierCut, MAX_PPM + 1, type(uint32).max));
        vm.assume(thawingPeriod <= MAX_THAWING_PERIOD);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidMaxVerifierCut.selector,
                maxVerifierCut
            )
        );
        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);
    }

    function test_ProvisionParameters_RevertIf_InvalidThawingPeriod(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.assume(maxVerifierCut <= MAX_PPM);
        thawingPeriod = uint64(bound(thawingPeriod, MAX_THAWING_PERIOD + 1, type(uint64).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidThawingPeriod.selector,
                thawingPeriod,
                MAX_THAWING_PERIOD
            )
        );
        staking.setProvisionParameters(users.indexer, subgraphDataServiceAddress, maxVerifierCut, thawingPeriod);
    }
}
