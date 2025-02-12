// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingExtension } from "../../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingLegacySlashTest is HorizonStakingTest {
    /*
     * MODIFIERS
     */

    modifier useLegacySlasher(address slasher) {
        bytes32 storageKey = keccak256(abi.encode(slasher, 18));
        vm.store(address(staking), storageKey, bytes32(uint256(1)));
        _;
    }

    /*
     * HELPERS
     */

    function _setIndexer(
        address _indexer,
        uint256 _tokensStaked,
        uint256 _tokensAllocated,
        uint256 _tokensLocked,
        uint256 _tokensLockedUntil
    ) public {
        bytes32 baseSlot = keccak256(abi.encode(_indexer, 14));

        vm.store(address(staking), bytes32(uint256(baseSlot)), bytes32(_tokensStaked));
        vm.store(address(staking), bytes32(uint256(baseSlot) + 1), bytes32(_tokensAllocated));
        vm.store(address(staking), bytes32(uint256(baseSlot) + 2), bytes32(_tokensLocked));
        vm.store(address(staking), bytes32(uint256(baseSlot) + 3), bytes32(_tokensLockedUntil));
    }

    /*
     * ACTIONS
     */

    function _legacySlash(address _indexer, uint256 _tokens, uint256 _rewards, address _beneficiary) internal {
        // before
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeRewardsDestinationBalance = token.balanceOf(_beneficiary);
        ServiceProviderInternal memory beforeIndexer = _getStorage_ServiceProviderInternal(_indexer);

        // calculate slashable stake
        uint256 slashableStake = beforeIndexer.tokensStaked - beforeIndexer.tokensProvisioned;
        uint256 actualTokens = _tokens;
        uint256 actualRewards = _rewards;
        if (slashableStake == 0) {
            actualTokens = 0;
            actualRewards = 0;
        } else if (_tokens > slashableStake) {
            actualRewards = (_rewards * slashableStake) / _tokens;
            actualTokens = slashableStake;
        }

        // slash
        vm.expectEmit(address(staking));
        emit IHorizonStakingExtension.StakeSlashed(_indexer, actualTokens, actualRewards, _beneficiary);
        staking.slash(_indexer, _tokens, _rewards, _beneficiary);

        // after
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterRewardsDestinationBalance = token.balanceOf(_beneficiary);
        ServiceProviderInternal memory afterIndexer = _getStorage_ServiceProviderInternal(_indexer);

        assertEq(beforeStakingBalance - actualTokens, afterStakingBalance);
        assertEq(beforeRewardsDestinationBalance, afterRewardsDestinationBalance - actualRewards);
        assertEq(afterIndexer.tokensStaked, beforeIndexer.tokensStaked - actualTokens);
    }

    /*
     * TESTS
     */
    function testSlash_Legacy(
        uint256 tokensStaked,
        uint256 tokensProvisioned,
        uint256 slashTokens,
        uint256 reward
    ) public useIndexer useLegacySlasher(users.legacySlasher) {
        vm.assume(tokensStaked > 0);
        vm.assume(tokensStaked <= MAX_STAKING_TOKENS);
        vm.assume(tokensProvisioned > 0);
        vm.assume(tokensProvisioned <= tokensStaked);
        slashTokens = bound(slashTokens, 1, tokensStaked);
        reward = bound(reward, 0, slashTokens);

        _stake(tokensStaked);
        _provision(users.indexer, subgraphDataServiceLegacyAddress, tokensProvisioned, 0, 0);

        resetPrank(users.legacySlasher);
        _legacySlash(users.indexer, slashTokens, reward, makeAddr("fisherman"));
    }

    function testSlash_Legacy_UsingLockedTokens(
        uint256 tokens,
        uint256 slashTokens,
        uint256 reward
    ) public useIndexer useLegacySlasher(users.legacySlasher) {
        vm.assume(tokens > 1);
        slashTokens = bound(slashTokens, 1, tokens);
        reward = bound(reward, 0, slashTokens);

        _setIndexer(users.indexer, tokens, 0, tokens, block.timestamp + 1);
        // Send tokens manually to staking
        token.transfer(address(staking), tokens);

        resetPrank(users.legacySlasher);
        _legacySlash(users.indexer, slashTokens, reward, makeAddr("fisherman"));
    }

    function testSlash_Legacy_UsingAllocatedTokens(
        uint256 tokens,
        uint256 slashTokens,
        uint256 reward
    ) public useIndexer useLegacySlasher(users.legacySlasher) {
        vm.assume(tokens > 1);
        slashTokens = bound(slashTokens, 1, tokens);
        reward = bound(reward, 0, slashTokens);

        _setIndexer(users.indexer, tokens, 0, tokens, 0);
        // Send tokens manually to staking
        token.transfer(address(staking), tokens);

        resetPrank(users.legacySlasher);
        staking.legacySlash(users.indexer, slashTokens, reward, makeAddr("fisherman"));
    }

    function testSlash_Legacy_RevertWhen_CallerNotSlasher(
        uint256 tokens,
        uint256 slashTokens,
        uint256 reward
    ) public useIndexer {
        vm.assume(tokens > 0);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        vm.expectRevert("!slasher");
        staking.legacySlash(users.indexer, slashTokens, reward, makeAddr("fisherman"));
    }

    function testSlash_Legacy_RevertWhen_RewardsOverSlashTokens(
        uint256 tokens,
        uint256 slashTokens,
        uint256 reward
    ) public useIndexer useLegacySlasher(users.legacySlasher) {
        vm.assume(tokens > 0);
        vm.assume(slashTokens > 0);
        vm.assume(reward > slashTokens);

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        resetPrank(users.legacySlasher);
        vm.expectRevert("rewards>slash");
        staking.legacySlash(users.indexer, slashTokens, reward, makeAddr("fisherman"));
    }

    function testSlash_Legacy_RevertWhen_NoStake(
        uint256 slashTokens,
        uint256 reward
    ) public useLegacySlasher(users.legacySlasher) {
        vm.assume(slashTokens > 0);
        reward = bound(reward, 0, slashTokens);

        resetPrank(users.legacySlasher);
        vm.expectRevert("!stake");
        staking.legacySlash(users.indexer, slashTokens, reward, makeAddr("fisherman"));
    }

    function testSlash_Legacy_RevertWhen_ZeroTokens(
        uint256 tokens
    ) public useIndexer useLegacySlasher(users.legacySlasher) {
        vm.assume(tokens > 0);

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        resetPrank(users.legacySlasher);
        vm.expectRevert("!tokens");
        staking.legacySlash(users.indexer, 0, 0, makeAddr("fisherman"));
    }

    function testSlash_Legacy_RevertWhen_NoBeneficiary(
        uint256 tokens,
        uint256 slashTokens,
        uint256 reward
    ) public useIndexer useLegacySlasher(users.legacySlasher) {
        vm.assume(tokens > 0);
        slashTokens = bound(slashTokens, 1, tokens);
        reward = bound(reward, 0, slashTokens);

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, 0);

        resetPrank(users.legacySlasher);
        vm.expectRevert("!beneficiary");
        staking.legacySlash(users.indexer, slashTokens, reward, address(0));
    }

    function test_LegacySlash_WhenTokensAllocatedGreaterThanStake()
        public
        useIndexer
        useLegacySlasher(users.legacySlasher)
    {
        // Setup indexer with:
        // - tokensStaked = 1000 GRT
        // - tokensAllocated = 800 GRT
        // - tokensLocked = 300 GRT
        // This means tokensUsed (1100 GRT) > tokensStaked (1000 GRT)
        _setIndexer(
            users.indexer,
            1000 ether, // tokensStaked
            800 ether, // tokensAllocated
            300 ether, // tokensLocked
            0 // tokensLockedUntil
        );

        // Send tokens manually to staking
        token.transfer(address(staking), 1100 ether);

        resetPrank(users.legacySlasher);
        _legacySlash(users.indexer, 1000 ether, 500 ether, makeAddr("fisherman"));
    }

    function test_LegacySlash_WhenDelegateCallFails() public useIndexer useLegacySlasher(users.legacySlasher) {
        // Setup indexer with:
        // - tokensStaked = 1000 GRT
        // - tokensAllocated = 800 GRT
        // - tokensLocked = 300 GRT

        _setIndexer(
            users.indexer,
            1000 ether, // tokensStaked
            800 ether, // tokensAllocated
            300 ether, // tokensLocked
            0 // tokensLockedUntil
        );

        // Send tokens manually to staking
        token.transfer(address(staking), 1100 ether);

        // Change staking extension code to an invalid opcode so the delegatecall reverts
        address stakingExtension = staking.getStakingExtension();
        vm.etch(stakingExtension, hex"fe");

        resetPrank(users.legacySlasher);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingLegacySlashFailed()");
        vm.expectRevert(expectedError);
        staking.slash(users.indexer, 1000 ether, 500 ether, makeAddr("fisherman"));
    }
}
