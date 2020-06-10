pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";


/**
 * @title A collection of data structures and functions to manage the Stake state
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 */
library Stakes {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    struct Allocation {
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        address channelID; // Indexer channel ID used off chain
    }

    struct Indexer {
        uint256 tokensStaked; // Tokens on the indexer stake (staked by the indexer)
        uint256 tokensAllocated; // Tokens used in allocations
        uint256 tokensLocked; // Tokens locked for withdrawal subject to thawing period
        uint256 tokensLockedUntil; // Time when locked tokens can be withdrawn
        // SubgraphDeployment stake allocation tracking : subgraphDeploymentID => Allocation
        mapping(bytes32 => Allocation) allocations;
    }

    /**
     * @dev Allocate tokens from the available stack to a SubgraphDeployment
     * @param stake Stake data
     * @param _subgraphDeploymentID SubgraphDeployment where to allocate tokens
     * @param _tokens Amount of tokens to allocate
     */
    function allocateTokens(
        Stakes.Indexer storage stake,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) internal returns (Allocation storage) {
        Stakes.Allocation storage alloc = stake.allocations[_subgraphDeploymentID];
        alloc.tokens = alloc.tokens.add(_tokens);
        stake.tokensAllocated = stake.tokensAllocated.add(_tokens);
        return alloc;
    }

    /**
     * @dev Unallocate tokens from a SubgraphDeployment
     * @param stake Stake data
     * @param _subgraphDeploymentID SubgraphDeployment from where to unallocate tokens
     * @param _tokens Amount of tokens to unallocate
     */
    function unallocateTokens(
        Stakes.Indexer storage stake,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) internal returns (Allocation storage) {
        Stakes.Allocation storage alloc = stake.allocations[_subgraphDeploymentID];
        alloc.tokens = alloc.tokens.sub(_tokens);
        stake.tokensAllocated = stake.tokensAllocated.sub(_tokens);
        return alloc;
    }

    /**
     * @dev Deposit tokens to the indexer stake
     * @param stake Stake data
     * @param _tokens Amount of tokens to deposit
     */
    function deposit(Stakes.Indexer storage stake, uint256 _tokens) internal {
        stake.tokensStaked = stake.tokensStaked.add(_tokens);
    }

    /**
     * @dev Release tokens from the indexer stake
     * @param stake Stake data
     * @param _tokens Amount of tokens to release
     */
    function release(Stakes.Indexer storage stake, uint256 _tokens) internal {
        stake.tokensStaked = stake.tokensStaked.sub(_tokens);
    }

    /**
     * @dev Lock tokens until a thawing period expires
     * @param stake Stake data
     * @param _tokens Amount of tokens to unstake
     * @param _thawingPeriod Period in blocks that need to pass before withdrawal
     */
    function lockTokens(
        Stakes.Indexer storage stake,
        uint256 _tokens,
        uint256 _thawingPeriod
    ) internal {
        // Take into account period averaging for multiple unstake requests
        uint256 lockingPeriod = _thawingPeriod;
        if (stake.tokensLocked > 0) {
            lockingPeriod = stake.getLockingPeriod(_tokens, _thawingPeriod);
        }

        // Update balances
        stake.tokensLocked = stake.tokensLocked.add(_tokens);
        stake.tokensLockedUntil = block.number.add(lockingPeriod);
    }

    /**
     * @dev Unlock tokens
     * @param stake Stake data
     * @param _tokens Amount of tokens to unkock
     */
    function unlockTokens(Stakes.Indexer storage stake, uint256 _tokens) internal {
        stake.tokensLocked = stake.tokensLocked.sub(_tokens);
        if (stake.tokensLocked == 0) {
            stake.tokensLockedUntil = 0;
        }
    }

    /**
     * @dev Take all tokens out from the locked stack for withdrawal
     * @param stake Stake data
     * @return Amount of tokens being withdrawn
     */
    function withdrawTokens(Stakes.Indexer storage stake) internal returns (uint256) {
        // Calculate tokens that can be released
        uint256 tokensToWithdraw = stake.tokensWithdrawable();

        if (tokensToWithdraw > 0) {
            // Reset locked tokens
            stake.unlockTokens(tokensToWithdraw);

            // Decrease indexer stake
            stake.release(tokensToWithdraw);
        }

        return tokensToWithdraw;
    }

    /**
     * @dev Get the locking period of the tokens to unstake, if already unstaked before calculate the weighted average
     * @param stake Stake data
     * @param _tokens Amount of tokens to unstake
     * @param _thawingPeriod Period in blocks that need to pass before withdrawal
     * @return True if staked
     */
    function getLockingPeriod(
        Stakes.Indexer storage stake,
        uint256 _tokens,
        uint256 _thawingPeriod
    ) internal view returns (uint256) {
        uint256 blockNum = block.number;
        uint256 periodA = (stake.tokensLockedUntil > blockNum)
            ? stake.tokensLockedUntil.sub(blockNum)
            : 0;
        uint256 periodB = _thawingPeriod;
        uint256 stakeA = stake.tokensLocked;
        uint256 stakeB = _tokens;
        return periodA.mul(stakeA).add(periodB.mul(stakeB)).div(stakeA.add(stakeB));
    }

    /**
     * @dev Return true if there are tokens staked by the Indexer
     * @param stake Stake data
     * @return True if staked
     */
    function hasTokens(Stakes.Indexer storage stake) internal view returns (bool) {
        return stake.tokensStaked > 0;
    }

    /**
     * @dev Return true if the indexer has allocated stake on the SubgraphDeployment
     * @param stake Stake data
     * @param _subgraphDeploymentID SubgraphDeployment for the allocation
     * @return True if allocated
     */
    function hasAllocation(Stakes.Indexer storage stake, bytes32 _subgraphDeploymentID)
        internal
        view
        returns (bool)
    {
        return stake.allocations[_subgraphDeploymentID].tokens > 0;
    }

    /**
     * @dev Tokens available for use in allocations
     * @dev tokensStaked - tokensAllocated - tokensLocked
     * @param stake Stake data
     * @return Token amount
     */
    function tokensAvailable(Stakes.Indexer storage stake) internal view returns (uint256) {
        uint256 tokensUsed = stake.tokensAllocated.add(stake.tokensLocked);
        // Stake is over allocated: return 0 to avoid stake to be used until the overallocation
        // is restored by staking more tokens or unallocating tokens
        if (tokensUsed > stake.tokensStaked) {
            return 0;
        }
        return stake.tokensStaked.sub(tokensUsed);
    }

    /**
     * @dev Tokens used for slashing whenever necessary
     * @param stake Stake data
     * @return Token amount
     */
    function tokensSlashable(Stakes.Indexer storage stake) internal view returns (uint256) {
        return stake.tokensStaked;
    }

    /**
     * @dev Tokens available for withdrawal after thawing period
     * @param stake Stake data
     * @return Token amount
     */
    function tokensWithdrawable(Stakes.Indexer storage stake) internal view returns (uint256) {
        // No tokens to withdraw before locking period
        if (stake.tokensLockedUntil == 0 || block.number < stake.tokensLockedUntil) {
            return 0;
        }
        // Cannot withdraw more than currently staked
        // This condition can happen if while tokens are locked for withdrawal a slash condition happens
        // In that case the total staked tokens could be below the amount to be withdrawn
        if (stake.tokensLocked > stake.tokensStaked) {
            return stake.tokensStaked;
        }
        return stake.tokensLocked;
    }

    /**
     * @dev Return if channel for an allocation is active
     * @param alloc Allocation data
     * @return True if channel related to allocation is active
     */
    function hasChannel(Stakes.Allocation storage alloc) internal view returns (bool) {
        return alloc.channelID != address(0);
    }

    /**
     * @dev Get the effective stake allocation considering epochs from allocation to settlement
     * @param alloc Allocation data
     * @param _numEpochs Number of epochs that passed from allocation to settlement
     * @param _maxEpochs Number of epochs used as a maximum to cap effective allocation
     * @return Effective allocated tokens accross epochs
     */
    function getTokensEffectiveAllocation(
        Stakes.Allocation storage alloc,
        uint256 _numEpochs,
        uint256 _maxEpochs
    ) internal view returns (uint256) {
        uint256 tokens = alloc.tokens;
        bool shouldCap = _maxEpochs > 0 && _numEpochs > _maxEpochs;
        return (shouldCap) ? tokens.mul(_maxEpochs) : tokens.mul(_numEpochs);
    }
}
