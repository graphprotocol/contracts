// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDataService } from "@graphprotocol/interfaces/contracts/data-service/IDataService.sol";
import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { Directory } from "../../../contracts/utilities/Directory.sol";
import { SubgraphServiceTest } from "./SubgraphService.t.sol";

contract SubgraphServiceSlashTest is SubgraphServiceTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_SubgraphService_Slash(
        uint256 tokens,
        uint256 tokensSlash,
        uint256 tokensReward
    ) public useIndexer useAllocation(tokens) {
        IHorizonStakingTypes.Provision memory provision = staking.getProvision(users.indexer, address(subgraphService));
        tokensSlash = bound(tokensSlash, 1, provision.tokens);
        uint256 maxVerifierTokens = tokensSlash.mulPPM(provision.maxVerifierCut);
        tokensReward = bound(tokensReward, 0, maxVerifierTokens);

        bytes memory data = abi.encode(tokensSlash, tokensReward);

        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceProviderSlashed(users.indexer, tokensSlash);

        resetPrank(address(disputeManager));
        subgraphService.slash(users.indexer, data);

        IHorizonStakingTypes.Provision memory provisionAfter = staking.getProvision(
            users.indexer,
            address(subgraphService)
        );
        assertEq(provisionAfter.tokens, provision.tokens - tokensSlash);
    }

    function test_SubgraphService_Slash_ZeroReward(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        IHorizonStakingTypes.Provision memory provision = staking.getProvision(users.indexer, address(subgraphService));
        tokensSlash = bound(tokensSlash, 1, provision.tokens);

        bytes memory data = abi.encode(tokensSlash, uint256(0));

        vm.expectEmit(address(subgraphService));
        emit IDataService.ServiceProviderSlashed(users.indexer, tokensSlash);

        resetPrank(address(disputeManager));
        subgraphService.slash(users.indexer, data);

        IHorizonStakingTypes.Provision memory provisionAfter = staking.getProvision(
            users.indexer,
            address(subgraphService)
        );
        assertEq(provisionAfter.tokens, provision.tokens - tokensSlash);
    }

    function test_SubgraphService_Slash_RevertWhen_RewardExceedsMax(
        uint256 tokens,
        uint256 tokensSlash,
        uint256 tokensReward
    ) public useIndexer useAllocation(tokens) {
        IHorizonStakingTypes.Provision memory provision = staking.getProvision(users.indexer, address(subgraphService));
        tokensSlash = bound(tokensSlash, 1, provision.tokens);
        uint256 maxVerifierTokens = tokensSlash.mulPPM(provision.maxVerifierCut);
        tokensReward = bound(tokensReward, maxVerifierTokens + 1, type(uint256).max);

        bytes memory data = abi.encode(tokensSlash, tokensReward);

        resetPrank(address(disputeManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingTooManyTokens.selector,
                tokensReward,
                maxVerifierTokens
            )
        );
        subgraphService.slash(users.indexer, data);
    }

    function test_SubgraphService_Slash_RevertWhen_NotDisputeManager(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes memory data = abi.encode(uint256(1), uint256(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                Directory.DirectoryNotDisputeManager.selector,
                users.indexer,
                address(disputeManager)
            )
        );
        subgraphService.slash(users.indexer, data);
    }
}
