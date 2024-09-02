// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { LinkedList } from "../../contracts/libraries/LinkedList.sol";
import { MathUtils } from "../../contracts/libraries/MathUtils.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingTest is HorizonStakingSharedTest {
    using stdStorage for StdStorage;

    /*
     * MODIFIERS
     */

    modifier usePausedStaking() {
        vm.startPrank(users.governor);
        controller.setPaused(true);
        vm.stopPrank();
        _;
    }

    modifier useThawAndDeprovision(uint256 amount, uint64 thawingPeriod) {
        vm.assume(amount > 0);
        _thaw(users.indexer, subgraphDataServiceAddress, amount);
        skip(thawingPeriod + 1);
        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
        _;
    }

    modifier useDelegation(uint256 delegationAmount) {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        vm.assume(delegationAmount > MIN_DELEGATION);
        vm.assume(delegationAmount <= MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
        vm.startPrank(msgSender);
        _;
    }

    modifier useLockedVerifier(address verifier) {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(users.governor);
        _setAllowedLockedVerifier(verifier, true);
        resetPrank(msgSender);
        _;
    }

    modifier useDelegationSlashing() {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(users.governor);
        staking.setDelegationSlashingEnabled();
        resetPrank(msgSender);
        _;
    }

    /*
     * HELPERS
     */

    function _slash(address serviceProvider, address verifier, uint256 tokens, uint256 verifierCutAmount) internal {
        uint256 beforeProviderTokens = staking.getProviderTokensAvailable(serviceProvider, verifier);
        uint256 beforeDelegationTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);
        bool isDelegationSlashingEnabled = staking.isDelegationSlashingEnabled();

        // Calculate expected tokens after slashing
        uint256 providerTokensSlashed = MathUtils.min(beforeProviderTokens, tokens);
        uint256 expectedProviderTokensAfterSlashing = beforeProviderTokens - providerTokensSlashed;

        uint256 delegationTokensSlashed = MathUtils.min(beforeDelegationTokens, tokens - providerTokensSlashed);
        uint256 expectedDelegationTokensAfterSlashing = beforeDelegationTokens -
            (isDelegationSlashingEnabled ? delegationTokensSlashed : 0);

        vm.expectEmit(address(staking));
        if (verifierCutAmount > 0) {
            emit IHorizonStakingMain.VerifierTokensSent(
                serviceProvider,
                verifier,
                verifier,
                verifierCutAmount
            );
        }
        emit IHorizonStakingMain.ProvisionSlashed(serviceProvider, verifier, providerTokensSlashed);

        if (isDelegationSlashingEnabled) {
            emit IHorizonStakingMain.DelegationSlashed(
                serviceProvider,
                verifier,
                delegationTokensSlashed
            );
        } else {
            emit IHorizonStakingMain.DelegationSlashingSkipped(
                serviceProvider,
                verifier,
                delegationTokensSlashed
            );
        }
        staking.slash(serviceProvider, tokens, verifierCutAmount, verifier);

        if (!isDelegationSlashingEnabled) {
            expectedDelegationTokensAfterSlashing = beforeDelegationTokens;
        }

        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, verifier);
        assertEq(provisionTokens, expectedProviderTokensAfterSlashing);

        uint256 delegationTokens = staking.getDelegatedTokensAvailable(serviceProvider, verifier);
        assertEq(delegationTokens, expectedDelegationTokensAfterSlashing);

        uint256 verifierTokens = token.balanceOf(verifier);
        assertEq(verifierTokens, verifierCutAmount);
    }

}
