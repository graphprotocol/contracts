// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingExtensionTest } from "./HorizonStakingExtension.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";
import { ExponentialRebates } from "../../../contracts/staking/libraries/ExponentialRebates.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

contract HorizonStakingCollectAllocationTest is HorizonStakingExtensionTest {
    using PPMMath for uint256;

    uint32 private alphaNumerator = 100;
    uint32 private alphaDenominator = 100;
    uint32 private lambdaNumerator = 60;
    uint32 private lambdaDenominator = 100;

    /*
     * MODIFIERS
     */

    modifier useRebateParameters() {
        _storeRebateParameters();
        _;
    }

    /*
     * HELPERS
     */

    function _storeRebateParameters() private {
        // Store alpha numerator and denominator
        uint256 alphaSlot = 13;
        uint256 alphaNumeratorOffset = 20;
        uint256 alphaDenominatorOffset = 24;
        bytes32 alphaValues = bytes32(
            (uint256(alphaNumerator) << (8 * alphaNumeratorOffset)) |
            (uint256(alphaDenominator) << (8 * alphaDenominatorOffset))
        );
        vm.store(address(staking), bytes32(alphaSlot), alphaValues);

        // Store lambda numerator and denominator
        uint256 lambdaSlot = 25;
        uint256 lambdaNumeratorOffset = 20;
        uint256 lambdaDenominatorOffset = 24;
        bytes32 lambdaValues = bytes32(
            (uint256(lambdaNumerator) << (8 * lambdaNumeratorOffset)) |
            (uint256(lambdaDenominator) << (8 * lambdaDenominatorOffset))
        );
        vm.store(address(staking), bytes32(lambdaSlot), lambdaValues);
    }

    function _storeProtocolTaxAndCuration(uint32 curationPercentage, uint32 taxPercentage) private {
        bytes32 slot = bytes32(uint256(13));
        uint256 curationOffset = 4;
        uint256 protocolTaxOffset = 8;
        bytes32 originalValue = vm.load(address(staking), slot);

        bytes32 newProtocolTaxValue = bytes32(
            (uint256(originalValue) & ~((0xFFFFFFFF << (8 * curationOffset)) | (0xFFFFFFFF << (8 * protocolTaxOffset))) | 
            (uint256(curationPercentage) << (8 * curationOffset))) |
            (uint256(taxPercentage) << (8 * protocolTaxOffset))
        );
        vm.store(address(staking), slot, newProtocolTaxValue);
    }

    /*
     * TESTS
     */

    function testCollectAllocation_RevertWhen_InvalidAllocationId(uint256 tokens) public useAllocation {
        vm.expectRevert("!alloc");
        staking.collect(tokens, address(0));
    }

    function testCollectAllocation_RevertWhen_Null(uint256 tokens) public {
        vm.expectRevert("!collect");
        staking.collect(tokens, _allocationId);
    }

    function testCollectAllocation_ZeroTokens() public useAllocation {
        staking.collect(0, _allocationId);
        assertEq(staking.getStake(address(users.indexer)), 0);
    }

    function testCollect_Tokens(
        uint256 provisionTokens,
        uint256 allocationTokens,
        uint256 collectTokens,
        uint256 curationTokens,
        uint32 curationPercentage,
        uint32 protocolTaxPercentage,
        uint256 delegationTokens,
        uint32 queryFeeCut
    ) public useRebateParameters {
        provisionTokens = bound(provisionTokens, 1, MAX_STAKING_TOKENS);
        allocationTokens = bound(allocationTokens, 0, MAX_STAKING_TOKENS);
        collectTokens = bound(collectTokens, 0, MAX_STAKING_TOKENS);
        curationTokens = bound(curationTokens, 0, MAX_STAKING_TOKENS);
        delegationTokens = bound(delegationTokens, 0, MAX_STAKING_TOKENS);
        vm.assume(curationPercentage <= MAX_PPM);
        vm.assume(protocolTaxPercentage <= MAX_PPM);
        vm.assume(queryFeeCut <= MAX_PPM);
        resetPrank(users.indexer);
        _createProvision(subgraphDataServiceLegacyAddress, provisionTokens, 0, 0);
        _storeAllocation(allocationTokens);
        _storeProtocolTaxAndCuration(curationPercentage, protocolTaxPercentage);
        _storeDelegationPool(delegationTokens, 0, queryFeeCut);
        curation.signal(_subgraphDeploymentID, curationTokens);

        resetPrank(users.gateway);
        approve(address(staking), collectTokens);
        staking.collect(collectTokens, _allocationId);

        uint256 protocolTaxTokens = collectTokens.mulPPMRoundUp(protocolTaxPercentage);
        uint256 queryFees = collectTokens - protocolTaxTokens;
        
        uint256 curationCutTokens = 0;
        if (curationTokens > 0) {
            curationCutTokens = queryFees.mulPPMRoundUp(curationPercentage);
            queryFees -= curationCutTokens;
        }
        
        uint256 newRebates = ExponentialRebates.exponentialRebates(
            queryFees,
            allocationTokens,
            alphaNumerator,
            alphaDenominator,
            lambdaNumerator,
            lambdaDenominator
        );
        uint256 payment = newRebates > queryFees ? queryFees : newRebates;

        uint256 delegationFeeCut = 0;
        if (delegationTokens > 0) {
            delegationFeeCut = payment - payment.mulPPM(queryFeeCut);
            payment -= delegationFeeCut;
        }

        assertEq(staking.getStake(address(users.indexer)), provisionTokens + payment);
        assertEq(curation.curation(_subgraphDeploymentID), curationTokens + curationCutTokens);
        assertEq(staking.getDelegationPool(users.indexer, subgraphDataServiceLegacyAddress).tokens, delegationTokens + delegationFeeCut);
    }

    function testCollect_WithBeneficiaryAddress(
        uint256 provisionTokens,
        uint256 allocationTokens,
        uint256 collectTokens
    ) public useIndexer useRebateParameters {
        provisionTokens = bound(provisionTokens, 1, MAX_STAKING_TOKENS);
        allocationTokens = bound(allocationTokens, 0, MAX_STAKING_TOKENS);
        collectTokens = bound(collectTokens, 0, MAX_STAKING_TOKENS);

        _createProvision(subgraphDataServiceLegacyAddress, provisionTokens, 0, 0);
        _storeAllocation(allocationTokens);

        address beneficiary = makeAddr("beneficiary");
        _storeRewardsDestination(beneficiary);

        resetPrank(users.gateway);
        approve(address(staking), collectTokens);
        staking.collect(collectTokens, _allocationId);

        uint256 newRebates = ExponentialRebates.exponentialRebates(
            collectTokens,
            allocationTokens,
            alphaNumerator,
            alphaDenominator,
            lambdaNumerator,
            lambdaDenominator
        );
        uint256 payment = newRebates > collectTokens ? collectTokens : newRebates;

        assertEq(token.balanceOf(beneficiary), payment);
    }
}