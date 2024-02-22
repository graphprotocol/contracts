// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Stakes.sol";

contract StakingMock {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    // -- State --

    uint256 public minimumIndexerStake = 100e18;
    uint256 public thawingPeriod = 10; // 10 blocks
    IERC20 public token;

    // Indexer stakes : indexer => Stake
    mapping(address => Stakes.Indexer) public stakes;

    /**
     * @dev Emitted when `indexer` stake `tokens` amount.
     */
    event StakeDeposited(address indexed indexer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` unstaked and locked `tokens` amount `until` block.
     */
    event StakeLocked(address indexed indexer, uint256 tokens, uint256 until);

    /**
     * @dev Emitted when `indexer` withdrew `tokens` staked.
     */
    event StakeWithdrawn(address indexed indexer, uint256 tokens);

    // Contract constructor.
    constructor(IERC20 _token) {
        require(address(_token) != address(0), "!token");
        token = _token;
    }

    receive() external payable {}

    /**
     * @dev Deposit tokens on the indexer stake.
     * @param _tokens Amount of tokens to stake
     */
    function stake(uint256 _tokens) external {
        stakeTo(msg.sender, _tokens);
    }

    /**
     * @dev Deposit tokens on the indexer stake.
     * @param _indexer Address of the indexer
     * @param _tokens Amount of tokens to stake
     */
    function stakeTo(address _indexer, uint256 _tokens) public {
        require(_tokens > 0, "!tokens");

        // Ensure minimum stake
        require(stakes[_indexer].tokensSecureStake().add(_tokens) >= minimumIndexerStake, "!minimumIndexerStake");

        // Transfer tokens to stake from caller to this contract
        require(token.transferFrom(msg.sender, address(this), _tokens), "!transfer");

        // Stake the transferred tokens
        _stake(_indexer, _tokens);
    }

    /**
     * @dev Unstake tokens from the indexer stake, lock them until thawing period expires.
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[indexer];

        require(_tokens > 0, "!tokens");
        require(indexerStake.hasTokens(), "!stake");
        require(indexerStake.tokensAvailable() >= _tokens, "!stake-avail");

        // Ensure minimum stake
        uint256 newStake = indexerStake.tokensSecureStake().sub(_tokens);
        require(newStake == 0 || newStake >= minimumIndexerStake, "!minimumIndexerStake");

        // Before locking more tokens, withdraw any unlocked ones
        uint256 tokensToWithdraw = indexerStake.tokensWithdrawable();
        if (tokensToWithdraw > 0) {
            _withdraw(indexer);
        }

        indexerStake.lockTokens(_tokens, thawingPeriod);

        emit StakeLocked(indexer, indexerStake.tokensLocked, indexerStake.tokensLockedUntil);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     */
    function withdraw() external {
        _withdraw(msg.sender);
    }

    function _stake(address _indexer, uint256 _tokens) internal {
        // Deposit tokens into the indexer stake
        Stakes.Indexer storage indexerStake = stakes[_indexer];
        indexerStake.deposit(_tokens);

        emit StakeDeposited(_indexer, _tokens);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     * @param _indexer Address of indexer to withdraw funds from
     */
    function _withdraw(address _indexer) private {
        // Get tokens available for withdraw and update balance
        uint256 tokensToWithdraw = stakes[_indexer].withdrawTokens();
        require(tokensToWithdraw > 0, "!tokens");

        // Return tokens to the indexer
        require(token.transfer(_indexer, tokensToWithdraw), "!transfer");

        emit StakeWithdrawn(_indexer, tokensToWithdraw);
    }
}
