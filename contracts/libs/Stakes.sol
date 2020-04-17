pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";


/*
 * @title A collection of data structures and functions to manage the Stake state
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 */

library Stakes {
    using SafeMath for uint256;
    using Stakes for Stakes.IndexNode;

    enum ChannelStatus { Closed, Active }

    struct Allocation {
        uint256 tokens; // Tokens allocated to a subgraph
        uint256 createdAtEpoch; // Epoch when it was created
        address channelID; // IndexNode payment channel ID used off chain
        ChannelStatus status; // Current status
    }

    struct IndexNode {
        uint256 tokens; // Tokens on the IndexNode stake
        uint256 tokensDelegated; // Tokens on the Delegated stake
        uint256 tokensAllocated; // Tokens used in subgraph allocations
        uint256 tokensLocked; // Tokens locked for withdrawal subject to thawing period
        uint256 tokensLockedUntil; // Date where locked tokens can be withdrawn
        mapping(bytes32 => Allocation) allocations; // Subgraph stake tracking
    }

    /**
     * @dev Allocate tokens from the available stack to a subgraph
     * @param stake Stake data
     * @param _subgraphID Subgraph where to allocate tokens
     * @param _tokens Amount of tokens to allocate
     */
    function allocateTokens(Stakes.IndexNode storage stake, bytes32 _subgraphID, uint256 _tokens)
        internal
        returns (Allocation storage)
    {
        Stakes.Allocation storage alloc = stake.allocations[_subgraphID];
        alloc.tokens = alloc.tokens.add(_tokens);
        stake.tokensAllocated = stake.tokensAllocated.add(_tokens);
        return alloc;
    }

    /**
     * @dev Unallocate tokens from a subgraph
     * @param stake Stake data
     * @param _subgraphID Subgraph from where to unallocate tokens
     * @param _tokens Amount of tokens to unallocate
     */
    function unallocateTokens(Stakes.IndexNode storage stake, bytes32 _subgraphID, uint256 _tokens)
        internal
        returns (Allocation storage)
    {
        Stakes.Allocation storage alloc = stake.allocations[_subgraphID];
        alloc.tokens = alloc.tokens.sub(_tokens);
        stake.tokensAllocated = stake.tokensAllocated.sub(_tokens);
        return alloc;
    }

    /**
     * @dev Deposit tokens to the index node stake balance
     * @param stake Stake data
     * @param _tokens Amount of tokens to deposit
     */
    function depositTokens(Stakes.IndexNode storage stake, uint256 _tokens) internal {
        stake.tokens = stake.tokens.add(_tokens);
    }

    /**
     * @dev Release tokens from the index node stake balance
     * @param stake Stake data
     * @param _tokens Amount of tokens to release
     */
    function releaseTokens(Stakes.IndexNode storage stake, uint256 _tokens) internal {
        stake.tokens = stake.tokens.sub(_tokens);
    }

    /**
     * @dev Lock tokens until a thawing period expires
     * @param stake Stake data
     * @param _tokens Amount of tokens to unstake
     * @param _thawingPeriod Period in blocks that need to pass before withdrawal
     */
    function lockTokens(Stakes.IndexNode storage stake, uint256 _tokens, uint256 _thawingPeriod)
        internal
    {
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
     * @dev Take all tokens out from the locked stack for withdrawal
     * @param stake Stake data
     * @return Amount of tokens being withdrawn
     */
    function withdrawTokens(Stakes.IndexNode storage stake) internal returns (uint256) {
        // Calculate tokens that can be released
        uint256 tokensToWithdraw = stake.tokensWithdrawable();

        if (tokensToWithdraw > 0) {
            // Reset locked tokens
            stake.tokensLocked = 0;
            stake.tokensLockedUntil = 0;

            // Decrease index node stake
            stake.releaseTokens(tokensToWithdraw);
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
        Stakes.IndexNode storage stake,
        uint256 _tokens,
        uint256 _thawingPeriod
    ) internal view returns (uint256) {
        uint256 blockNum = block.number;
        uint256 periodA = (stake.tokensLockedUntil > blockNum)
            ? stake.tokensLockedUntil.sub(blockNum)
            : 0;
        uint256 periodB = _thawingPeriod;
        uint256 valueA = stake.tokensLocked;
        uint256 valueB = _tokens;
        return periodA.mul(valueA).add(periodB.mul(valueB)).div(valueA.add(valueB));
    }

    /**
     * @dev Return true if there are tokens staked by the IndexNode
     * @param stake Stake data
     * @return True if staked
     */
    function hasTokens(Stakes.IndexNode storage stake) internal view returns (bool) {
        return stake.tokens > 0;
    }

    /**
     * @dev Total tokens staked both from IndexNode and Delegators
     * @param stake Stake data
     * @return Token amount
     */
    function tokensStaked(Stakes.IndexNode storage stake) internal view returns (uint256) {
        return stake.tokens.add(stake.tokensDelegated);
    }

    /**
     * @dev Tokens available for use in allocations
     * @param stake Stake data
     * @return Token amount
     */
    function tokensAvailable(Stakes.IndexNode storage stake) internal view returns (uint256) {
        return stake.tokensStaked().sub(stake.tokensAllocated).sub(stake.tokensLocked);
    }

    /**
     * @dev Tokens used for slashing whenever necessary
     * @param stake Stake data
     * @return Token amount
     */
    function tokensSlashable(Stakes.IndexNode storage stake) internal view returns (uint256) {
        return stake.tokens;
    }

    /**
     * @dev Tokens available for withdrawal after thawing period
     * @param stake Stake data
     * @return Token amount
     */
    function tokensWithdrawable(Stakes.IndexNode storage stake) internal view returns (uint256) {
        if (block.number < stake.tokensLockedUntil) {
            return 0;
        }
        // TODO: take into account there could be less tokens because of slashing
        return stake.tokensLocked;
    }

    /**
     * @dev Return if channel for an allocation is active
     * @param alloc Allocation data
     * @return True if payment channel related to allocation is active
     */
    function hasActiveChannel(Stakes.Allocation storage alloc) internal view returns (bool) {
        return alloc.status == Stakes.ChannelStatus.Active;
    }
}
