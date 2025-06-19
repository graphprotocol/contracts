// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementBaseTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_GetIndexingAgreement(Seed memory seed, address operator, bytes16 agreementId) public {
        vm.assume(_isSafeSubgraphServiceCaller(operator));

        resetPrank(address(operator));

        // Get unkown indexing agreement
        vm.expectRevert(abi.encodeWithSelector(IndexingAgreement.IndexingAgreementNotActive.selector, agreementId));
        subgraphService.getIndexingAgreement(agreementId);

        // Accept an indexing agreement
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);
        IndexingAgreement.AgreementWrapper memory agreement = subgraphService.getIndexingAgreement(
            accepted.rca.agreementId
        );
        _assertEqualAgreement(accepted.rca, agreement);
    }

    function test_SubgraphService_Revert_WhenUnsafeAddress_WhenProxyAdmin(address indexer, bytes16 agreementId) public {
        address operator = _transparentUpgradeableProxyAdmin();
        assertFalse(_isSafeSubgraphServiceCaller(operator));

        vm.expectRevert(TransparentUpgradeableProxy.ProxyDeniedAdminAccess.selector);
        resetPrank(address(operator));
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_Revert_WhenUnsafeAddress_WhenGraphProxyAdmin(uint256 unboundedTokens) public {
        address indexer = GRAPH_PROXY_ADMIN_ADDRESS;
        assertFalse(_isSafeSubgraphServiceCaller(indexer));

        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        vm.expectRevert("Cannot fallback to proxy target");
        staking.provision(indexer, address(subgraphService), tokens, maxSlashingPercentage, disputePeriod);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
