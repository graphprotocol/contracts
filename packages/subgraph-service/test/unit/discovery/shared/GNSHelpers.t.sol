// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DiscoveryTest } from "./DiscoveryTest.t.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";

/// Ports the `lib/gnsUtils.ts` helpers used by the L2GNS tests, assertions included.
abstract contract GNSHelpers is DiscoveryTest {
    uint32 internal constant DEFAULT_RESERVE_RATIO = 1_000_000;
    uint256 internal constant MAX_PPM = 1_000_000;

    uint8 internal constant RECEIVE_SUBGRAPH_CODE = 0;
    uint8 internal constant RECEIVE_CURATOR_BALANCE_CODE = 1;

    bytes32 internal constant DEPLOYMENT_ID_0 = keccak256("subgraphDeploymentID0");
    bytes32 internal constant DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");

    struct Subgraph {
        uint256 vSignal;
        uint256 nSignal;
        bytes32 subgraphDeploymentID;
        uint32 reserveRatio;
        bool disabled;
        uint256 withdrawableGRT;
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(governor);
        grt.mint(me, 10_000 ether);
    }

    function _versionMetadata(bytes32 deploymentId) internal pure returns (bytes32) {
        return keccak256(abi.encode("versionMetadata", deploymentId));
    }

    function _subgraphMetadata(bytes32 deploymentId) internal pure returns (bytes32) {
        return keccak256(abi.encode("subgraphMetadata", deploymentId));
    }

    function _subgraph(uint256 subgraphId) internal view returns (Subgraph memory s) {
        (s.vSignal, s.nSignal, s.subgraphDeploymentID, s.reserveRatio, s.disabled, s.withdrawableGRT) = gns.subgraphs(
            subgraphId
        );
    }

    function _tokensAndVSignal(bytes32 deploymentId) internal view returns (uint256 tokens, uint256 vSignal) {
        (tokens, , ) = curation.pools(deploymentId);
        vSignal = curation.getCurationPoolSignal(deploymentId);
    }

    // -- L1 transfers (from l2GNS.test.ts) --

    uint256 internal constant L1_CURATED_TOKENS = 1337 ether;
    bytes32 internal constant L1_SUBGRAPH_METADATA = keccak256("l1SubgraphMetadata");
    bytes32 internal constant L1_VERSION_METADATA = keccak256("l1VersionMetadata");

    function _l1SubgraphId() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(me, uint256(1), block.chainid)));
    }

    function _callhookData(uint8 code, uint256 l1SubgraphId, address beneficiary) internal pure returns (bytes memory) {
        return abi.encode(code, l1SubgraphId, beneficiary);
    }

    /// Receives the subgraph from L1 and finishes the transfer on DEPLOYMENT_ID_0, as `me`
    function _transferMockSubgraphFromL1(uint256 l1SubgraphId, uint256 curatedTokens) internal {
        gatewayMock.deliver(address(gns), l1GNS, curatedTokens, _callhookData(RECEIVE_SUBGRAPH_CODE, l1SubgraphId, me));
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(l1SubgraphId);
        vm.prank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, L1_SUBGRAPH_METADATA, L1_VERSION_METADATA);
    }

    function _publishNewSubgraph(address account, bytes32 deploymentId) internal returns (uint256 subgraphId) {
        subgraphId = uint256(keccak256(abi.encodePacked(account, gns.nextAccountSeqID(account), block.chainid)));
        bytes32 versionMetadata = _versionMetadata(deploymentId);
        bytes32 subgraphMetadata = _subgraphMetadata(deploymentId);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphPublished(subgraphId, deploymentId, DEFAULT_RESERVE_RATIO);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphMetadataUpdated(subgraphId, subgraphMetadata);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(subgraphId, deploymentId, versionMetadata);
        vm.prank(account);
        gns.publishNewSubgraph(deploymentId, versionMetadata, subgraphMetadata);

        Subgraph memory s = _subgraph(subgraphId);
        assertEq(s.vSignal, 0);
        assertEq(s.nSignal, 0);
        assertEq(s.subgraphDeploymentID, deploymentId);
        assertEq(s.reserveRatio, DEFAULT_RESERVE_RATIO);
        assertFalse(s.disabled);
        assertEq(s.withdrawableGRT, 0);

        assertEq(gns.ownerOf(subgraphId), account);
    }

    /// Mirrors GNS._chargeOwnerTax (the helper's formula only matches it when the division is exact)
    function _ownerTaxAdjusted(
        uint256 tokens,
        uint32 curationTaxPercentage,
        uint32 ownerTaxPercentage
    ) internal pure returns (uint256) {
        if (curationTaxPercentage == 0 || ownerTaxPercentage == 0) return tokens;
        uint256 taxOnOriginal = (tokens * curationTaxPercentage) / MAX_PPM;
        uint256 totalWithoutOwnerTax = tokens - taxOnOriginal;
        uint256 ownerTax = (taxOnOriginal * ownerTaxPercentage) / MAX_PPM;
        uint256 totalWithOwnerTax = totalWithoutOwnerTax + ownerTax;
        return (totalWithOwnerTax * MAX_PPM) / (MAX_PPM - curationTaxPercentage);
    }

    struct VersionUpgrade {
        uint256 totalAdjustedUp;
        uint256 newVSignalEstimate;
        uint256 newCurationTaxEstimate;
        uint256 beforeTokensNewCurve;
        uint256 beforeVSignalNewCurve;
    }

    function _estimateVersionUpgrade(
        uint256 subgraphId,
        uint256 nSignal,
        bytes32 newDeploymentId
    ) internal view returns (VersionUpgrade memory u) {
        if (nSignal > 0) {
            // No tax on burning nSignal
            (, uint256 tokensReceivedEstimate) = gns.nSignalToTokens(subgraphId, nSignal);
            u.totalAdjustedUp = _ownerTaxAdjusted(
                tokensReceivedEstimate,
                curation.curationTaxPercentage(),
                gns.ownerTaxPercentage()
            );
            (u.newVSignalEstimate, u.newCurationTaxEstimate) = curation.tokensToSignal(
                newDeploymentId,
                u.totalAdjustedUp
            );
        }
        (u.beforeTokensNewCurve, u.beforeVSignalNewCurve) = _tokensAndVSignal(newDeploymentId);
    }

    function _publishNewVersion(address account, uint256 subgraphId, bytes32 newDeploymentId) internal {
        Subgraph memory beforeSubgraph = _subgraph(subgraphId);
        VersionUpgrade memory u = _estimateVersionUpgrade(subgraphId, beforeSubgraph.nSignal, newDeploymentId);

        // Only emits SubgraphUpgraded if there was signal to upgrade
        if (beforeSubgraph.nSignal > 0) {
            vm.expectEmit(address(gns));
            emit IL2GNSLike.SubgraphUpgraded(subgraphId, u.newVSignalEstimate, u.totalAdjustedUp, newDeploymentId);
        }
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(subgraphId, newDeploymentId, _versionMetadata(newDeploymentId));
        vm.prank(account);
        gns.publishNewVersion(subgraphId, newDeploymentId, _versionMetadata(newDeploymentId), 0);

        // Old curve is emptied
        (uint256 afterTokensOldCurve, uint256 afterVSignalOldCurve) = _tokensAndVSignal(
            beforeSubgraph.subgraphDeploymentID
        );
        assertEq(afterTokensOldCurve, 0);
        assertEq(afterVSignalOldCurve, 0);

        (uint256 afterTokensNewCurve, uint256 afterVSignalNewCurve) = _tokensAndVSignal(newDeploymentId);
        assertEq(afterTokensNewCurve, u.beforeTokensNewCurve + u.totalAdjustedUp - u.newCurationTaxEstimate);
        assertEq(afterVSignalNewCurve, u.beforeVSignalNewCurve + u.newVSignalEstimate);

        Subgraph memory afterSubgraph = _subgraph(subgraphId);
        assertEq(afterSubgraph.vSignal, afterVSignalNewCurve - u.beforeVSignalNewCurve);
        assertEq(afterSubgraph.vSignal, u.newVSignalEstimate);
        assertEq(afterSubgraph.nSignal, beforeSubgraph.nSignal);
        assertEq(afterSubgraph.subgraphDeploymentID, newDeploymentId);

        assertEq(gns.ownerOf(subgraphId), account);
    }

    function _mintSignal(address account, uint256 subgraphId, uint256 tokensIn) internal {
        Subgraph memory beforeSubgraph = _subgraph(subgraphId);
        (uint256 beforeTokens, uint256 beforeVSignal) = _tokensAndVSignal(beforeSubgraph.subgraphDeploymentID);

        (uint256 vSignalExpected, uint256 nSignalExpected, uint256 curationTax) = gns.tokensToNSignal(
            subgraphId,
            tokensIn
        );
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SignalMinted(subgraphId, account, nSignalExpected, vSignalExpected, tokensIn);
        vm.prank(account);
        gns.mintSignal(subgraphId, tokensIn, 0);

        Subgraph memory afterSubgraph = _subgraph(subgraphId);
        (uint256 afterTokens, uint256 afterVSignal) = _tokensAndVSignal(afterSubgraph.subgraphDeploymentID);
        assertEq(afterTokens, beforeTokens + tokensIn - curationTax);
        assertEq(afterVSignal, beforeVSignal + vSignalExpected);
        assertEq(afterSubgraph.nSignal, beforeSubgraph.nSignal + nSignalExpected);
        assertEq(afterSubgraph.vSignal, beforeVSignal + vSignalExpected);
    }

    function _burnSignal(address account, uint256 subgraphId) internal {
        Subgraph memory beforeSubgraph = _subgraph(subgraphId);
        (uint256 beforeTokens, uint256 beforeVSignal) = _tokensAndVSignal(beforeSubgraph.subgraphDeploymentID);
        uint256 beforeUsersNSignal = gns.getCuratorSignal(subgraphId, account);

        (uint256 vSignalExpected, uint256 tokensExpected) = gns.nSignalToTokens(subgraphId, beforeUsersNSignal);
        assertEq(gns.nSignalToVSignal(subgraphId, beforeUsersNSignal), vSignalExpected);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SignalBurned(subgraphId, account, beforeUsersNSignal, vSignalExpected, tokensExpected);
        vm.prank(account);
        gns.burnSignal(subgraphId, beforeUsersNSignal, 0);

        Subgraph memory afterSubgraph = _subgraph(subgraphId);
        (uint256 afterTokens, uint256 afterVSignal) = _tokensAndVSignal(afterSubgraph.subgraphDeploymentID);
        assertEq(afterTokens, beforeTokens - tokensExpected);
        assertEq(afterVSignal, beforeVSignal - vSignalExpected);
        assertEq(afterSubgraph.nSignal, beforeSubgraph.nSignal - beforeUsersNSignal);
    }

    function _deprecateSubgraph(address account, uint256 subgraphId) internal {
        Subgraph memory beforeSubgraph = _subgraph(subgraphId);
        (uint256 beforeTokens, ) = _tokensAndVSignal(beforeSubgraph.subgraphDeploymentID);
        // All vSignal in these tests is held by the subgraph's nSignal, so the whole pool is withdrawable
        uint256 ownerBalanceBefore = grt.balanceOf(account);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphDeprecated(subgraphId, beforeTokens);
        vm.prank(account);
        gns.deprecateSubgraph(subgraphId);

        Subgraph memory afterSubgraph = _subgraph(subgraphId);
        assertTrue(afterSubgraph.disabled);
        assertEq(afterSubgraph.vSignal, 0);
        assertEq(afterSubgraph.reserveRatio, 0);
        assertEq(afterSubgraph.withdrawableGRT, beforeTokens);

        assertEq(grt.balanceOf(address(gns)), afterSubgraph.withdrawableGRT);
        assertEq(grt.balanceOf(account), ownerBalanceBefore);

        // NFT is burned
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        gns.ownerOf(subgraphId);
    }
}
