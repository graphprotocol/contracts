// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

// solhint-disable named-parameters-mapping
// solhint-disable gas-strict-inequalities

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Stakes } from "./Stakes.sol";

/**
 * @title StakingMock contract
 * @author Edge & Node
 * @notice A mock contract for testing staking functionality
 */
contract StakingMock {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    // -- State --

    /// @notice Minimum stake required for indexers
    uint256 public minimumIndexerStake = 100e18;
    /// @notice Thawing period in blocks
    uint256 public thawingPeriod = 10; // 10 blocks
    /// @notice The token contract
    IERC20 public token;

    /// @notice Indexer stakes mapping
    mapping(address => Stakes.Indexer) public stakes;

    /**
     * @notice Emitted when indexer stakes tokens
     * @param indexer The indexer address
     * @param tokens The amount of tokens staked
     */
    event StakeDeposited(address indexed indexer, uint256 indexed tokens);

    /**
     * @notice Emitted when indexer unstakes and locks tokens
     * @param indexer The indexer address
     * @param tokens The amount of tokens locked
     * @param until The block number until which tokens are locked
     */
    event StakeLocked(address indexed indexer, uint256 indexed tokens, uint256 indexed until);

    /**
     * @notice Emitted when indexer withdraws staked tokens
     * @param indexer The indexer address
     * @param tokens The amount of tokens withdrawn
     */
    event StakeWithdrawn(address indexed indexer, uint256 indexed tokens);

    /**
     * @notice Contract constructor
     * @param _token The token contract address
     */
    constructor(IERC20 _token) {
        require(address(_token) != address(0), "!token");
        token = _token;
    }

    /// @notice Receive function to accept ETH
    receive() external payable {}

    /**
     * @notice Deposit tokens on the indexer stake
     * @param _tokens Amount of tokens to stake
     */
    function stake(uint256 _tokens) external {
        stakeTo(msg.sender, _tokens);
    }

    /**
     * @notice Deposit tokens on the indexer stake
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
     * @notice Unstake tokens from the indexer stake, lock them until thawing period expires
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
     * @notice Withdraw indexer tokens once the thawing period has passed
     */
    function withdraw() external {
        _withdraw(msg.sender);
    }

    /**
     * @notice Internal function to stake tokens for an indexer
     * @param _indexer Address of the indexer
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexer, uint256 _tokens) internal {
        // Deposit tokens into the indexer stake
        Stakes.Indexer storage indexerStake = stakes[_indexer];
        indexerStake.deposit(_tokens);

        emit StakeDeposited(_indexer, _tokens);
    }

    /**
     * @notice Withdraw indexer tokens once the thawing period has passed
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
