// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "../shared/GNSHelpers.t.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";

contract PublishNewVersionTest is GNSHelpers {
    uint256 internal constant TOKENS_1000 = 1000 ether;
    uint256 internal constant TOKENS_10000 = 10_000 ether;
    uint256 internal constant TOKENS_100000 = 100_000 ether;
    uint32 internal constant CURATION_TAX_PERCENTAGE = 50_000;

    uint256 internal subgraphId;

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);
        grt.mint(me, TOKENS_100000);
        grt.mint(other, TOKENS_100000);
        curation.setCurationTaxPercentage(CURATION_TAX_PERCENTAGE);
        vm.stopPrank();
        vm.startPrank(me);
        grt.approve(address(gns), TOKENS_100000);
        grt.approve(address(curation), TOKENS_100000);
        vm.stopPrank();
        vm.startPrank(other);
        grt.approve(address(gns), TOKENS_100000);
        grt.approve(address(curation), TOKENS_100000);
        vm.stopPrank();

        subgraphId = _publishNewSubgraph(me, DEPLOYMENT_ID_0);
        _mintSignal(me, subgraphId, TOKENS_10000);
    }

    function test_PublishNewVersion_OnExistingSubgraph() public {
        _publishNewVersion(me, subgraphId, DEPLOYMENT_ID_1);
    }

    function test_PublishNewVersion_WhenOwnerTaxIsZero() public {
        vm.prank(governor);
        gns.setOwnerTaxPercentage(0);
        _publishNewVersion(me, subgraphId, DEPLOYMENT_ID_1);
    }

    function test_PublishNewVersion_WithNoCurrentSignal() public {
        uint256 emptySignalSubgraphId = _publishNewSubgraph(me, keccak256("emptySignalDeploymentID"));
        _publishNewVersion(me, emptySignalSubgraphId, DEPLOYMENT_ID_1);
    }

    function test_PublishNewVersion_RevertWhen_SameDeploymentID() public {
        vm.expectRevert(bytes("GNS: Cannot publish a new version with the same subgraph deployment ID"));
        vm.prank(me);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_0, _versionMetadata(DEPLOYMENT_ID_0), 0);
    }

    function test_PublishNewVersion_RevertWhen_SubgraphDoesNotExist() public {
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        vm.prank(me);
        gns.publishNewVersion(
            uint256(keccak256("nonexistentSubgraph")),
            DEPLOYMENT_ID_1,
            _versionMetadata(DEPLOYMENT_ID_1),
            0
        );
    }

    function test_PublishNewVersion_RevertWhen_NotOwner() public {
        vm.expectRevert(bytes("GNS: Must be authorized"));
        vm.prank(other);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1), 0);
    }

    function test_PublishNewVersion_ToPreCuratedDeployment() public {
        // Curate directly to the deployment
        vm.prank(me);
        curation.mint(DEPLOYMENT_ID_1, TOKENS_1000, 0);

        _publishNewVersion(me, subgraphId, DEPLOYMENT_ID_1);
    }

    function test_PublishNewVersion_WithNoSignalNoMigration() public {
        _burnSignal(me, subgraphId);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1));
        vm.prank(me);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1), 0);
    }

    function test_PublishNewVersion_RevertWhen_Deprecated() public {
        _deprecateSubgraph(me, subgraphId);

        // Deprecate burns the subgraph NFT, so the ownership check can't find it
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        vm.prank(me);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1), 0);
    }

    function test_PublishNewVersion_RevertWhen_FrontRunBeyondSlippage() public {
        // Give attacker massive funds for the attack
        vm.prank(governor);
        grt.mint(attacker, 1_000_000 ether);
        vm.prank(attacker);
        grt.approve(address(curation), 1_000_000 ether);

        // Set minimum curation deposit to 1 wei and disable tax for an accurate attack test
        vm.startPrank(governor);
        curation.setMinimumCurationDeposit(1);
        curation.setCurationTaxPercentage(0);
        vm.stopPrank();
        vm.prank(attacker);
        curation.mint(DEPLOYMENT_ID_1, 1, 0);

        // Expected signal from burning the current subgraph (before the attack)
        uint256 vSignal = _subgraph(subgraphId).vSignal;
        uint256 tokensFromOldCurve = curation.signalToTokens(DEPLOYMENT_ID_0, vSignal);
        uint256 expectedSignalWithoutAttack = curation.tokensToSignalNoTax(DEPLOYMENT_ID_1, tokensFromOldCurve);

        // Attacker inflates the curation pool by collecting massive query fees
        uint256 collectTokens = 50_000 ether;
        vm.prank(governor);
        grt.mint(address(curation), collectTokens);
        vm.prank(subgraphService);
        curation.collect(DEPLOYMENT_ID_1, collectTokens);

        // The victim now gets much less signal
        uint256 actualSignalAfterAttack = curation.tokensToSignalNoTax(DEPLOYMENT_ID_1, tokensFromOldCurve);
        assertLt(actualSignalAfterAttack, expectedSignalWithoutAttack / 10);

        // With slippage protection the upgrade fails when expecting reasonable signal
        vm.expectRevert(bytes("Slippage protection"));
        vm.prank(me);
        gns.publishNewVersion(
            subgraphId,
            DEPLOYMENT_ID_1,
            _versionMetadata(DEPLOYMENT_ID_1),
            expectedSignalWithoutAttack / 2
        );
    }

    function test_PublishNewVersion_WhenSlippageProtectionSatisfied() public {
        // Pre-curate the new deployment
        vm.prank(governor);
        grt.mint(attacker, 100 ether);
        vm.startPrank(attacker);
        grt.approve(address(curation), 100 ether);
        curation.mint(DEPLOYMENT_ID_1, 100 ether, 0);
        vm.stopPrank();

        // Minimum signal we accept (5% slippage)
        uint256 vSignal = _subgraph(subgraphId).vSignal;
        uint256 tokensFromOldCurve = curation.signalToTokens(DEPLOYMENT_ID_0, vSignal);
        uint256 expectedSignal = curation.tokensToSignalNoTax(DEPLOYMENT_ID_1, tokensFromOldCurve);
        uint256 minSignalWithSlippage = (expectedSignal * 95) / 100;

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1));
        vm.prank(me);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1), minSignalWithSlippage);
    }

    function test_PublishNewVersion_L1VersionWhenNotPreCurated() public {
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1));
        vm.prank(me);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1));
    }

    function test_PublishNewVersion_RevertWhen_L1VersionPreCurated() public {
        vm.prank(me);
        curation.mint(DEPLOYMENT_ID_1, TOKENS_1000, 0);

        vm.expectRevert(bytes("GNS: Owner cannot point to a subgraphID that has been pre-curated"));
        vm.prank(me);
        gns.publishNewVersion(subgraphId, DEPLOYMENT_ID_1, _versionMetadata(DEPLOYMENT_ID_1));
    }
}
