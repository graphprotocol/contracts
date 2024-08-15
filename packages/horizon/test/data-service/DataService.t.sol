// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { DataServiceBase } from "./implementations/DataServiceBase.sol";
import { DataServiceOverride } from "./implementations/DataServiceOverride.sol";
import { ProvisionManager } from "./../../contracts/data-service/utilities/ProvisionManager.sol";
import { PPMMath } from "./../../contracts/libraries/PPMMath.sol";

contract DataServiceTest is HorizonStakingSharedTest {
    DataServiceBase dataService;
    DataServiceOverride dataServiceOverride;

    function setUp() public override {
        super.setUp();

        dataService = new DataServiceBase(address(controller));
        dataServiceOverride = new DataServiceOverride(address(controller));
    }

    function test_Constructor_WhenTheContractIsDeployedWithAValidController() external view {
        _assert_delegationRatio(type(uint32).min);
        _assert_provisionTokens_range(type(uint256).min, type(uint256).max);
        _assert_verifierCut_range(type(uint32).min, type(uint32).max);
        _assert_thawingPeriod_range(type(uint64).min, type(uint64).max);
    }

    // -- Delegation ratio --

    function test_DelegationRatio_WhenSettingTheDelegationRatio(uint32 delegationRatio) external {
        _assert_set_delegationRatio(delegationRatio);
    }

    function test_DelegationRatio_WhenGettingTheDelegationRatio(uint32 ratio) external {
        dataService.setDelegationRatio(ratio);
        _assert_delegationRatio(ratio);
    }

    // -- Provision tokens --

    function test_ProvisionTokens_WhenSettingAValidRange(uint256 min, uint256 max) external {
        vm.assume(min <= max);
        _assert_set_provisionTokens_range(min, max);
    }

    function test_ProvisionTokens_RevertWhen_SettingAnInvalidRange(uint256 min, uint256 max) external {
        vm.assume(min > max);

        vm.expectRevert(abi.encodeWithSelector(ProvisionManager.ProvisionManagerInvalidRange.selector, min, max));
        dataService.setProvisionTokensRange(min, max);
    }

    function test_ProvisionTokens_WhenGettingTheRange() external {
        dataService.setProvisionTokensRange(dataService.PROVISION_TOKENS_MIN(), dataService.PROVISION_TOKENS_MAX());
        _assert_provisionTokens_range(dataService.PROVISION_TOKENS_MIN(), dataService.PROVISION_TOKENS_MAX());
    }

    function test_ProvisionTokens_WhenGettingTheRangeWithAnOverridenGetter() external {
        // Overriden getter returns the const values regardless of the set range
        dataServiceOverride.setProvisionTokensRange(0, 1);
        (uint256 min, uint256 max) = dataServiceOverride.getProvisionTokensRange();

        assertEq(min, dataServiceOverride.PROVISION_TOKENS_MIN());
        assertEq(max, dataServiceOverride.PROVISION_TOKENS_MAX());
    }

    function test_ProvisionTokens_WhenCheckingAValidProvision(uint256 tokens) external useIndexer {
        dataService.setProvisionTokensRange(dataService.PROVISION_TOKENS_MIN(), dataService.PROVISION_TOKENS_MAX());
        tokens = bound(tokens, dataService.PROVISION_TOKENS_MIN(), dataService.PROVISION_TOKENS_MAX());

        _createProvision(address(dataService), tokens, 0, 0);
        dataService.checkProvisionTokens(users.indexer);
    }

    function test_ProvisionTokens_WhenCheckingWithAnOverridenChecker(uint256 tokens) external useIndexer {
        vm.assume(tokens != 0);
        dataServiceOverride.setProvisionTokensRange(
            dataService.PROVISION_TOKENS_MIN(),
            dataService.PROVISION_TOKENS_MAX()
        );

        // this checker accepts provisions with any amount of tokens
        _createProvision(address(dataServiceOverride), tokens, 0, 0);
        dataServiceOverride.checkProvisionTokens(users.indexer);
    }

    function test_ProvisionTokens_RevertWhen_CheckingAnInvalidProvision(uint256 tokens) external useIndexer {
        dataService.setProvisionTokensRange(dataService.PROVISION_TOKENS_MIN(), dataService.PROVISION_TOKENS_MAX());
        tokens = bound(tokens, 1, dataService.PROVISION_TOKENS_MIN() - 1);

        _createProvision(address(dataService), tokens, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "tokens",
                tokens,
                dataService.PROVISION_TOKENS_MIN(),
                dataService.PROVISION_TOKENS_MAX()
            )
        );
        dataService.checkProvisionTokens(users.indexer);
    }

    // -- Verifier cut --

    function test_VerifierCut_WhenSettingAValidRange(uint32 min, uint32 max) external {
        vm.assume(min <= max);
        _assert_set_verifierCut_range(min, max);
    }

    function test_VerifierCut_RevertWhen_SettingAnInvalidRange(uint32 min, uint32 max) external {
        vm.assume(min > max);

        vm.expectRevert(abi.encodeWithSelector(ProvisionManager.ProvisionManagerInvalidRange.selector, min, max));
        dataService.setVerifierCutRange(min, max);
    }

    function test_VerifierCut_WhenGettingTheRange() external {
        dataService.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
        _assert_verifierCut_range(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
    }

    function test_VerifierCut_WhenGettingTheRangeWithAnOverridenGetter() external {
        // Overriden getter returns the const values regardless of the set range
        dataServiceOverride.setVerifierCutRange(0, 1);
        (uint32 min, uint32 max) = dataServiceOverride.getVerifierCutRange();
        assertEq(min, dataServiceOverride.VERIFIER_CUT_MIN());
        assertEq(max, dataServiceOverride.VERIFIER_CUT_MAX());
    }

    function test_VerifierCut_WhenCheckingAValidProvision(uint32 verifierCut) external useIndexer {
        dataService.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
        verifierCut = uint32(bound(verifierCut, dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX()));

        _createProvision(address(dataService), dataService.PROVISION_TOKENS_MIN(), verifierCut, 0);
        dataService.checkProvisionParameters(users.indexer, false);
    }

    function test_VerifierCut_WhenCheckingWithAnOverridenChecker(uint32 verifierCut) external useIndexer {
        verifierCut = uint32(bound(verifierCut, 0, uint32(PPMMath.MAX_PPM)));
        dataServiceOverride.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());

        // this checker accepts provisions with any verifier cut range
        _createProvision(address(dataService), dataService.PROVISION_TOKENS_MIN(), verifierCut, 0);
        dataServiceOverride.checkProvisionParameters(users.indexer, false);
    }

    function test_VerifierCut_RevertWhen_CheckingAnInvalidProvision(uint32 verifierCut) external useIndexer {
        dataService.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
        verifierCut = uint32(bound(verifierCut, 0, dataService.VERIFIER_CUT_MIN() - 1));

        _createProvision(address(dataService), dataService.PROVISION_TOKENS_MIN(), verifierCut, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "maxVerifierCut",
                verifierCut,
                dataService.VERIFIER_CUT_MIN(),
                dataService.VERIFIER_CUT_MAX()
            )
        );
        dataService.checkProvisionParameters(users.indexer, false);
    }

    // -- Thawing period --

    function test_ThawingPeriod_WhenSettingAValidRange(uint64 min, uint64 max) external {
        vm.assume(min <= max);
        _assert_set_thawingPeriod_range(min, max);
    }

    function test_ThawingPeriod_RevertWhen_SettingAnInvalidRange(uint64 min, uint64 max) external {
        vm.assume(min > max);

        vm.expectRevert(abi.encodeWithSelector(ProvisionManager.ProvisionManagerInvalidRange.selector, min, max));
        dataService.setThawingPeriodRange(min, max);
    }

    function test_ThawingPeriod_WhenGettingTheRange() external {
        dataService.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());
        _assert_thawingPeriod_range(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());
    }

    function test_ThawingPeriod_WhenGettingTheRangeWithAnOverridenGetter() external {
        // Overriden getter returns the const values regardless of the set range
        dataServiceOverride.setThawingPeriodRange(0, 1);
        (uint64 min, uint64 max) = dataServiceOverride.getThawingPeriodRange();
        assertEq(min, dataServiceOverride.THAWING_PERIOD_MIN());
        assertEq(max, dataServiceOverride.THAWING_PERIOD_MAX());
    }

    function test_ThawingPeriod_WhenCheckingAValidProvision(uint64 thawingPeriod) external useIndexer {
        dataService.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());
        thawingPeriod = uint32(
            bound(thawingPeriod, dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX())
        );

        _createProvision(address(dataService), dataService.PROVISION_TOKENS_MIN(), 0, thawingPeriod);
        dataService.checkProvisionParameters(users.indexer, false);
    }

    function test_ThawingPeriod_WhenCheckingWithAnOverridenChecker(uint64 thawingPeriod) external useIndexer {
        thawingPeriod = uint32(bound(thawingPeriod, 0, staking.getMaxThawingPeriod()));
        dataServiceOverride.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());

        // this checker accepts provisions with any verifier cut range
        _createProvision(address(dataService), dataService.PROVISION_TOKENS_MIN(), 0, thawingPeriod);
        dataServiceOverride.checkProvisionParameters(users.indexer, false);
    }

    function test_ThawingPeriod_RevertWhen_CheckingAnInvalidProvision(uint64 thawingPeriod) external useIndexer {
        dataService.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());
        thawingPeriod = uint32(bound(thawingPeriod, 0, dataService.THAWING_PERIOD_MIN() - 1));

        _createProvision(address(dataService), dataService.PROVISION_TOKENS_MIN(), 0, thawingPeriod);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "thawingPeriod",
                thawingPeriod,
                dataService.THAWING_PERIOD_MIN(),
                dataService.THAWING_PERIOD_MAX()
            )
        );
        dataService.checkProvisionParameters(users.indexer, false);
    }

    modifier givenProvisionParametersChanged() {
        _;
    }

    function test_ProvisionParameters_WhenTheNewParametersAreValid(
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external givenProvisionParametersChanged useIndexer {
        // bound to valid values
        maxVerifierCut = uint32(bound(maxVerifierCut, dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX()));
        thawingPeriod = uint64(
            bound(thawingPeriod, dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX())
        );

        // set provision parameter ranges
        dataService.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
        dataService.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());

        // stage provision parameter changes
        _createProvision(
            address(dataService),
            dataService.PROVISION_TOKENS_MIN(),
            dataService.VERIFIER_CUT_MIN(),
            dataService.THAWING_PERIOD_MIN()
        );
        staking.setProvisionParameters(users.indexer, address(dataService), maxVerifierCut, thawingPeriod);

        // accept provision parameters
        if (maxVerifierCut != dataService.VERIFIER_CUT_MIN() || thawingPeriod != dataService.THAWING_PERIOD_MIN()) {
            vm.expectEmit();
            emit IHorizonStakingMain.ProvisionParametersSet(
                users.indexer,
                address(dataService),
                maxVerifierCut,
                thawingPeriod
            );
        }
        dataService.acceptProvisionParameters(users.indexer);
    }

    function test_ProvisionParameters_RevertWhen_TheNewThawingPeriodIsInvalid(
        uint64 thawingPeriod
    ) external givenProvisionParametersChanged useIndexer {
        // bound to invalid values
        thawingPeriod = uint64(bound(thawingPeriod, 0, dataService.THAWING_PERIOD_MIN() - 1));

        // set provision parameter ranges
        dataService.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
        dataService.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());

        // stage provision parameter changes
        _createProvision(
            address(dataService),
            dataService.PROVISION_TOKENS_MIN(),
            dataService.VERIFIER_CUT_MIN(),
            dataService.THAWING_PERIOD_MIN()
        );
        staking.setProvisionParameters(
            users.indexer,
            address(dataService),
            dataService.VERIFIER_CUT_MIN(),
            thawingPeriod
        );

        // accept provision parameters
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionManager.ProvisionManagerInvalidValue.selector,
                "thawingPeriod",
                thawingPeriod,
                dataService.THAWING_PERIOD_MIN(),
                dataService.THAWING_PERIOD_MAX()
            )
        );
        dataService.acceptProvisionParameters(users.indexer);
    }

    function test_ProvisionParameters_RevertWhen_TheNewVerifierCutIsInvalid(
        uint32 maxVerifierCut
    ) external givenProvisionParametersChanged useIndexer {
        // bound to valid values
        maxVerifierCut = uint32(bound(maxVerifierCut, dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX()));

        // set provision parameter ranges
        dataService.setVerifierCutRange(dataService.VERIFIER_CUT_MIN(), dataService.VERIFIER_CUT_MAX());
        dataService.setThawingPeriodRange(dataService.THAWING_PERIOD_MIN(), dataService.THAWING_PERIOD_MAX());

        // stage provision parameter changes
        _createProvision(
            address(dataService),
            dataService.PROVISION_TOKENS_MIN(),
            dataService.VERIFIER_CUT_MIN(),
            dataService.THAWING_PERIOD_MIN()
        );
        staking.setProvisionParameters(
            users.indexer,
            address(dataService),
            maxVerifierCut,
            dataService.THAWING_PERIOD_MIN()
        );

        // accept provision parameters
        if (maxVerifierCut != dataService.VERIFIER_CUT_MIN()) {
            vm.expectEmit();
            emit IHorizonStakingMain.ProvisionParametersSet(
                users.indexer,
                address(dataService),
                maxVerifierCut,
                dataService.THAWING_PERIOD_MIN()
            );
        }
        dataService.acceptProvisionParameters(users.indexer);
    }

    // -- Assert functions --

    function _assert_set_delegationRatio(uint32 ratio) internal {
        vm.expectEmit();
        emit ProvisionManager.DelegationRatioSet(ratio);
        dataService.setDelegationRatio(ratio);
        _assert_delegationRatio(ratio);
    }

    function _assert_delegationRatio(uint32 ratio) internal view {
        uint32 _delegationRatio = dataService.getDelegationRatio();
        assertEq(_delegationRatio, ratio);
    }

    function _assert_set_provisionTokens_range(uint256 min, uint256 max) internal {
        vm.expectEmit();
        emit ProvisionManager.ProvisionTokensRangeSet(min, max);
        dataService.setProvisionTokensRange(min, max);
        _assert_provisionTokens_range(min, max);
    }

    function _assert_provisionTokens_range(uint256 min, uint256 max) internal view {
        (uint256 _min, uint256 _max) = dataService.getProvisionTokensRange();
        assertEq(_min, min);
        assertEq(_max, max);
    }

    function _assert_set_verifierCut_range(uint32 min, uint32 max) internal {
        vm.expectEmit();
        emit ProvisionManager.VerifierCutRangeSet(min, max);
        dataService.setVerifierCutRange(min, max);
        _assert_verifierCut_range(min, max);
    }

    function _assert_verifierCut_range(uint32 min, uint32 max) internal view {
        (uint32 _min, uint32 _max) = dataService.getVerifierCutRange();
        assertEq(_min, min);
        assertEq(_max, max);
    }

    function _assert_set_thawingPeriod_range(uint64 min, uint64 max) internal {
        vm.expectEmit();
        emit ProvisionManager.ThawingPeriodRangeSet(min, max);
        dataService.setThawingPeriodRange(min, max);
        _assert_thawingPeriod_range(min, max);
    }

    function _assert_thawingPeriod_range(uint64 min, uint64 max) internal view {
        (uint64 _min, uint64 _max) = dataService.getThawingPeriodRange();
        assertEq(_min, min);
        assertEq(_max, max);
    }
}
