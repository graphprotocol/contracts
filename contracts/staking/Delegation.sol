// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "./StakingStorage.sol";

contract Delegation is StakingV1Storage {
    using SafeMath for uint256;

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    /**
     * @dev Emitted when `delegator` delegated `tokens` to the `indexer`, the delegator
     * gets `shares` for the delegation pool proportionally to the tokens staked.
     */
    event StakeDelegated(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares
    );

    /**
     * @dev Emitted when `delegator` undelegated `tokens` from `indexer`.
     * Tokens get locked for withdrawal after a period of time.
     */
    event StakeDelegatedLocked(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares,
        uint256 until
    );

    /**
     * @dev Emitted when `delegator` withdrew delegated `tokens` from `indexer`.
     */
    event StakeDelegatedWithdrawn(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens
    );

    /**
     * @dev Emitted when `indexer` update the delegation parameters for its delegation pool.
     */
    event DelegationParametersUpdated(
        address indexed indexer,
        uint32 indexingRewardCut,
        uint32 queryFeeCut,
        uint32 cooldownBlocks
    );

    /**
     * @dev Set the delegation parameters.
     * @param _indexingRewardCut Percentage of indexing rewards left for delegators
     * @param _queryFeeCut Percentage of query fees left for delegators
     * @param _cooldownBlocks Period that need to pass to update delegation parameters
     */
    function setDelegationParameters(
        uint32 _indexingRewardCut,
        uint32 _queryFeeCut,
        uint32 _cooldownBlocks
    ) public {
        address indexer = msg.sender;

        // Incentives must be within bounds
        require(_queryFeeCut <= MAX_PPM, ">queryFeeCut");
        require(_indexingRewardCut <= MAX_PPM, ">indexingRewardCut");

        // Cooldown period set by indexer cannot be below protocol global setting
        require(_cooldownBlocks >= delegationParametersCooldown, "<cooldown");

        // Verify the cooldown period passed
        DelegationPool storage pool = delegationPools[indexer];
        require(
            pool.updatedAtBlock == 0 ||
                pool.updatedAtBlock.add(uint256(pool.cooldownBlocks)) <= block.number,
            "!cooldown"
        );

        // Update delegation params
        pool.indexingRewardCut = _indexingRewardCut;
        pool.queryFeeCut = _queryFeeCut;
        pool.cooldownBlocks = _cooldownBlocks;
        pool.updatedAtBlock = block.number;

        emit DelegationParametersUpdated(
            indexer,
            _indexingRewardCut,
            _queryFeeCut,
            _cooldownBlocks
        );
    }

    /**
     * @dev Delegate tokens to an indexer.
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     * @return Amount of shares issued of the delegation pool
     */
    function delegate(address _indexer, uint256 _tokens)
        external
        notPartialPaused
        returns (uint256)
    {
        address delegator = msg.sender;

        // Transfer tokens to delegate to this contract
        require(graphToken().transferFrom(delegator, address(this), _tokens), "!transfer");

        // Update state
        return _delegate(delegator, _indexer, _tokens);
    }

    /**
     * @dev Undelegate tokens from an indexer.
     * @param _indexer Address of the indexer where tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function undelegate(address _indexer, uint256 _shares)
        external
        notPartialPaused
        returns (uint256)
    {
        return _undelegate(msg.sender, _indexer, _shares);
    }

    /**
     * @dev Withdraw delegated tokens once the unbonding period has passed.
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _delegateToIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function withdrawDelegated(address _indexer, address _delegateToIndexer)
        external
        notPaused
        returns (uint256)
    {
        return _withdrawDelegated(msg.sender, _indexer, _delegateToIndexer);
    }

    /**
     * @dev Delegate tokens to an indexer.
     * @param _delegator Address of the delegator
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     * @return Amount of shares issued of the delegation pool
     */
    function _delegate(
        address _delegator,
        address _indexer,
        uint256 _tokens
    ) private returns (uint256) {
        // Only delegate a non-zero amount of tokens
        require(_tokens > 0, "!tokens");
        // Only delegate to non-empty address
        require(_indexer != address(0), "!indexer");
        // Only delegate to staked indexer
        require(stakes[_indexer].tokensStaked > 0, "!stake");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        DelegationData storage delegation = pool.delegators[_delegator];

        // Collect delegation tax
        uint256 delegationTax = _collectTax(graphToken(), _tokens, delegationTaxPercentage);
        uint256 delegatedTokens = _tokens.sub(delegationTax);

        // Calculate shares to issue
        uint256 shares =
            (pool.tokens == 0)
                ? delegatedTokens
                : delegatedTokens.mul(pool.shares).div(pool.tokens);

        // Update the delegation pool
        pool.tokens = pool.tokens.add(delegatedTokens);
        pool.shares = pool.shares.add(shares);

        // Update the delegation
        delegation.shares = delegation.shares.add(shares);

        emit StakeDelegated(_indexer, _delegator, delegatedTokens, shares);

        return shares;
    }

    /**
     * @dev Undelegate tokens from an indexer.
     * @param _delegator Address of the delegator
     * @param _indexer Address of the indexer where tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function _undelegate(
        address _delegator,
        address _indexer,
        uint256 _shares
    ) private returns (uint256) {
        // Can only undelegate a non-zero amount of shares
        require(_shares > 0, "!shares");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        DelegationData storage delegation = pool.delegators[_delegator];

        // Delegator need to have enough shares in the pool to undelegate
        require(delegation.shares >= _shares, "!shares-avail");

        // Withdraw tokens if available
        if (_getWithdraweableDelegatedTokens(delegation) > 0) {
            _withdrawDelegated(_delegator, _indexer, address(0));
        }

        // Calculate tokens to get in exchange for the shares
        uint256 tokens = _shares.mul(pool.tokens).div(pool.shares);

        // Update the delegation pool
        pool.tokens = pool.tokens.sub(tokens);
        pool.shares = pool.shares.sub(_shares);

        // Update the delegation
        delegation.shares = delegation.shares.sub(_shares);
        delegation.tokensLocked = delegation.tokensLocked.add(tokens);
        delegation.tokensLockedUntil = epochManager().currentEpoch().add(delegationUnbondingPeriod);

        emit StakeDelegatedLocked(
            _indexer,
            _delegator,
            tokens,
            _shares,
            delegation.tokensLockedUntil
        );

        return tokens;
    }

    /**
     * @dev Withdraw delegated tokens once the unbonding period has passed.
     * @param _delegator Delegator that is withdrawing tokens
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _delegateToIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function _withdrawDelegated(
        address _delegator,
        address _indexer,
        address _delegateToIndexer
    ) private returns (uint256) {
        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        DelegationData storage delegation = pool.delegators[_delegator];

        // Validation
        uint256 tokensToWithdraw = _getWithdraweableDelegatedTokens(delegation);
        require(tokensToWithdraw > 0, "!tokens");

        // Reset lock
        delegation.tokensLocked = 0;
        delegation.tokensLockedUntil = 0;

        emit StakeDelegatedWithdrawn(_indexer, _delegator, tokensToWithdraw);

        // -- Interactions --

        if (_delegateToIndexer != address(0)) {
            // Re-delegate tokens to a new indexer
            _delegate(_delegator, _delegateToIndexer, tokensToWithdraw);
        } else {
            // Return tokens to the delegator
            require(graphToken().transfer(_delegator, tokensToWithdraw), "!transfer");
        }

        return tokensToWithdraw;
    }

    /**
     * @dev Returns amount of delegated tokens ready to be withdrawn after unbonding period.
     * @param _delegation Delegation of tokens from delegator to indexer
     * @return Amount of tokens to withdraw
     */
    function _getWithdraweableDelegatedTokens(DelegationData memory _delegation)
        internal
        view
        returns (uint256)
    {
        // There must be locked tokens and period passed
        uint256 currentEpoch = epochManager().currentEpoch();
        if (_delegation.tokensLockedUntil > 0 && currentEpoch >= _delegation.tokensLockedUntil) {
            return _delegation.tokensLocked;
        }
        return 0;
    }

    /**
     * @dev Collect tax to burn for an amount of tokens.
     * @param _graphToken Token to burn
     * @param _tokens Total tokens received used to calculate the amount of tax to collect
     * @param _percentage Percentage of tokens to burn as tax
     * @return Amount of tax charged
     */
    function _collectTax(
        IGraphToken _graphToken,
        uint256 _tokens,
        uint256 _percentage
    ) private returns (uint256) {
        uint256 tax = uint256(_percentage).mul(_tokens).div(MAX_PPM);
        _burnTokens(_graphToken, tax); // Burn tax if any
        return tax;
    }

    /**
     * @dev Burn tokens held by this contract.
     * @param _graphToken Token to burn
     * @param _amount Amount of tokens to burn
     */
    function _burnTokens(IGraphToken _graphToken, uint256 _amount) private {
        if (_amount > 0) {
            _graphToken.burn(_amount);
        }
    }
}
