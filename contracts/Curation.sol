pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";
import "./GraphToken.sol";
import "./bancor/BancorFormula.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title Curation contract
 * @dev Allows curators to signal on subgraph deployments that might be relevant to indexers by
 * staking Graph Tokens. Additionally, curators earn fees from the Query Market related to the
 * subgraph deployment they curate.
 * A curators stake goes to a curation pool along with the stakes of other curators,
 * only one pool exists for each subgraph deployment.
 */
contract Curation is Governed, BancorFormula {
    using SafeMath for uint256;

    // -- Curation --

    struct CurationPool {
        uint256 reserveRatio; // Ratio for the bonding curve
        uint256 tokens; // Tokens stored as reserves for the SubgraphDeployment
        uint256 shares; // Shares issued for the SubgraphDeployment
        mapping(address => uint256) curatorShares; // Mapping of curator => shares
    }

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // Amount of shares you get with your minimum token stake
    uint256 private constant SHARES_PER_MINIMUM_STAKE = 1 ether;

    // -- State --

    // Default reserve ratio to configure curator shares bonding curve
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public defaultReserveRatio;

    // Minimum amount allowed to be staked by curators
    // This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationStake;

    // Fee charged when curator withdraw stake
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public withdrawalFeePercentage;

    // Mapping of subgraphDeploymentID => CurationPool
    // There is only one CurationPool per SubgraphDeployment
    mapping(bytes32 => CurationPool) public pools;

    // Address of the staking contract that will distribute fees to reserves
    address public staking;

    // Token used for staking
    GraphToken public token;

    // -- Events --

    /**
     * @dev Emitted when `curator` staked `tokens` on `subgraphDeploymentID` as curation signal.
     * The `curator` receives `shares` amount according to the curation pool bonding curve.
     */
    event Staked(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 shares
    );

    /**
     * @dev Emitted when `curator` redeemed `shares` for a `subgraphDeploymentID`.
     * The curator will receive `tokens` according to the value of the bonding curve.
     * An amount of `withdrawalFees` will be collected and burned.
     */
    event Redeemed(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 shares,
        uint256 withdrawalFees
    );

    /**
     * @dev Emitted when `tokens` amount were collected for `subgraphDeploymentID` as part of fees
     * distributed by an indexer from the settlement of query fees.
     */
    event Collected(bytes32 indexed subgraphDeploymentID, uint256 tokens);

    /**
     * @dev Contract Constructor.
     * @param _governor Owner address of this contract
     * @param _token Address of the Graph Protocol token
     * @param _defaultReserveRatio Reserve ratio to initialize the bonding curve of CurationPool
     * @param _minimumCurationStake Minimum amount of tokens that curators can stake
     */
    constructor(
        address _governor,
        address _token,
        uint256 _defaultReserveRatio,
        uint256 _minimumCurationStake
    ) public Governed(_governor) {
        token = GraphToken(_token);
        _setDefaultReserveRatio(_defaultReserveRatio);
        _setMinimumCurationStake(_minimumCurationStake);
    }

    /**
     * @dev Set the default reserve ratio percentage for a curation pool.
     * @notice Update the default reserver ratio to `_defaultReserveRatio`
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint256 _defaultReserveRatio) external onlyGovernor {
        _setDefaultReserveRatio(_defaultReserveRatio);
    }

    /**
     * @dev Set the default reserve ratio percentage for a curation pool.
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function _setDefaultReserveRatio(uint256 _defaultReserveRatio) private {
        // Reserve Ratio must be within 0% to 100% (exclusive, in PPM)
        require(_defaultReserveRatio > 0, "Default reserve ratio must be > 0");
        require(
            _defaultReserveRatio <= MAX_PPM,
            "Default reserve ratio cannot be higher than MAX_PPM"
        );

        defaultReserveRatio = _defaultReserveRatio;
        emit ParameterUpdated("defaultReserveRatio");
    }

    /**
     * @dev Set the staking contract used for fees distribution.
     * @notice Update the staking contract to `_staking`
     * @param _staking Address of the staking contract
     */
    function setStaking(address _staking) external onlyGovernor {
        staking = _staking;
        emit ParameterUpdated("staking");
    }

    /**
     * @dev Set the minimum stake amount for curators.
     * @notice Update the minimum stake amount to `_minimumCurationStake`
     * @param _minimumCurationStake Minimum amount of tokens required stake
     */
    function setMinimumCurationStake(uint256 _minimumCurationStake) external onlyGovernor {
        _setMinimumCurationStake(_minimumCurationStake);
    }

    /**
     * @dev Set the minimum stake amount for curators.
     * @param _minimumCurationStake Minimum amount of tokens required stake
     */
    function _setMinimumCurationStake(uint256 _minimumCurationStake) private {
        require(_minimumCurationStake > 0, "Minimum curation stake cannot be 0");
        minimumCurationStake = _minimumCurationStake;
        emit ParameterUpdated("minimumCurationStake");
    }

    /**
     * @dev Set the fee percentage to charge when a curator withdraws stake.
     * @param _percentage Percentage fee charged when withdrawing stake
     */
    function setWithdrawalFeePercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(
            _percentage <= MAX_PPM,
            "Withdrawal fee percentage must be below or equal to MAX_PPM"
        );
        withdrawalFeePercentage = _percentage;
        emit ParameterUpdated("withdrawalFeePercentage");
    }

    /**
     * @dev Assign Graph Tokens collected as curation fees to the curation pool reserve.
     * @param _subgraphDeploymentID SubgraphDeployment where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external {
        require(msg.sender == staking, "Caller must be the staking contract");

        // Transfer tokens collected from the staking contract to this contract
        require(
            token.transferFrom(staking, address(this), _tokens),
            "Cannot transfer tokens to collect"
        );

        // Collect tokens and assign them to the reserves
        _collect(_subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Stake Graph Tokens in exchange for shares of a SubgraphDeployment curation pool.
     * @param _subgraphDeploymentID SubgraphDeployment where the curator is staking Graph Tokens
     * @param _tokens Amount of Graph Tokens to stake
     */
    function stake(bytes32 _subgraphDeploymentID, uint256 _tokens) external {
        address curator = msg.sender;

        // Need to stake some funds
        require(_tokens > 0, "Cannot stake zero tokens");

        // Transfer tokens from the curator to this contract
        require(
            token.transferFrom(curator, address(this), _tokens),
            "Cannot transfer tokens to stake"
        );

        // Stake tokens to a curation pool reserve
        _stake(curator, _subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Return an amount of shares to get tokens back.
     * @notice Redeem _shares from the SubgraphDeployment curation pool
     * @param _subgraphDeploymentID SubgraphDeployment the curator is returning shares
     * @param _shares Amount of shares to return
     */
    function redeem(bytes32 _subgraphDeploymentID, uint256 _shares) external {
        address curator = msg.sender;
        CurationPool storage curationPool = pools[_subgraphDeploymentID];

        require(_shares > 0, "Cannot redeem zero shares");
        require(
            curationPool.curatorShares[curator] >= _shares,
            "Cannot redeem more shares than you own"
        );

        // Update balance and get the amount of tokens to refund based on returned shares
        uint256 tokens = _sellShares(curator, _subgraphDeploymentID, _shares);

        // If all shares redeemed delete the curation pool
        if (curationPool.shares == 0) {
            delete pools[_subgraphDeploymentID];
        }

        // Calculate withdrawal fees and burn the tokens
        uint256 withdrawalFees = percentageOf(withdrawalFeePercentage, tokens);
        if (withdrawalFees > 0) {
            tokens = tokens.sub(withdrawalFees);
            token.burn(withdrawalFees);
        }

        // Return the tokens to the curator
        require(token.transfer(curator, tokens), "Error sending curator tokens");

        emit Redeemed(curator, _subgraphDeploymentID, tokens, _shares, withdrawalFees);
    }

    /**
     * @dev Check if any Graph tokens are staked for a SubgraphDeployment.
     * @param _subgraphDeploymentID SubgraphDeployment to check if curated
     * @return True if curated
     */
    function isCurated(bytes32 _subgraphDeploymentID) public view returns (bool) {
        return pools[_subgraphDeploymentID].tokens > 0;
    }

    /**
     * @dev Get the number of shares a curator has on a curation pool.
     * @param _curator Curator owning the shares
     * @param _subgraphDeploymentID SubgraphDeployment of issued shares
     * @return Number of shares owned by a curator for the SubgraphDeployment
     */
    function getCuratorShares(address _curator, bytes32 _subgraphDeploymentID)
        public
        view
        returns (uint256)
    {
        return pools[_subgraphDeploymentID].curatorShares[_curator];
    }

    /**
     * @dev Calculate number of shares that can be bought with tokens in a curation pool.
     * @param _subgraphDeploymentID SubgraphDeployment to buy shares
     * @param _tokens Amount of tokens used to buy shares
     * @return Amount of shares that can be bought
     */
    function tokensToShares(bytes32 _subgraphDeploymentID, uint256 _tokens)
        public
        view
        returns (uint256)
    {
        // Handle initialization of bonding curve
        uint256 tokens = _tokens;
        uint256 shares = 0;
        CurationPool memory curationPool = pools[_subgraphDeploymentID];
        if (curationPool.tokens == 0) {
            curationPool = CurationPool(
                defaultReserveRatio,
                minimumCurationStake,
                SHARES_PER_MINIMUM_STAKE
            );
            tokens = tokens.sub(curationPool.tokens);
            shares = curationPool.shares;
        }

        return
            calculatePurchaseReturn(
                curationPool.shares,
                curationPool.tokens,
                uint32(curationPool.reserveRatio),
                tokens
            ) + shares;
    }

    /**
     * @dev Calculate number of tokens to get when selling shares from a curation pool.
     * @param _subgraphDeploymentID SubgraphDeployment to sell shares
     * @param _shares Amount of shares to sell
     * @return Amount of tokens to get after selling shares
     */
    function sharesToTokens(bytes32 _subgraphDeploymentID, uint256 _shares)
        public
        view
        returns (uint256)
    {
        CurationPool memory curationPool = pools[_subgraphDeploymentID];
        require(
            curationPool.tokens > 0,
            "SubgraphDeployment must be curated to perform calculations"
        );
        require(
            curationPool.shares >= _shares,
            "Shares must be above or equal to shares issued in the curation pool"
        );
        return
            calculateSaleReturn(
                curationPool.shares,
                curationPool.tokens,
                uint32(curationPool.reserveRatio),
                _shares
            );
    }

    /**
     * @dev Update balances after buy of shares and deposit of tokens.
     * @param _curator Curator
     * @param _subgraphDeploymentID SubgraphDeployment
     * @param _tokens Amount of tokens
     * @return Number of shares bought
     */
    function _buyShares(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) private returns (uint256) {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        uint256 shares = tokensToShares(_subgraphDeploymentID, _tokens);

        // Update tokens
        curationPool.tokens = curationPool.tokens.add(_tokens);

        // Update shares
        curationPool.shares = curationPool.shares.add(shares);
        curationPool.curatorShares[_curator] = curationPool.curatorShares[_curator].add(shares);

        return shares;
    }

    /**
     * @dev Update balances after sell of shares and return of tokens.
     * @param _curator Curator
     * @param _subgraphDeploymentID SubgraphDeployment
     * @param _shares Amount of shares
     * @return Number of tokens received
     */
    function _sellShares(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _shares
    ) private returns (uint256) {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        uint256 tokens = sharesToTokens(_subgraphDeploymentID, _shares);

        // Update tokens
        curationPool.tokens = curationPool.tokens.sub(tokens);

        // Update shares
        curationPool.shares = curationPool.shares.sub(_shares);
        curationPool.curatorShares[_curator] = curationPool.curatorShares[_curator].sub(_shares);

        return tokens;
    }

    /**
     * @dev Assign Graph Tokens received from staking to the curation pool reserve.
     * @param _subgraphDeploymentID SubgraphDeployment where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function _collect(bytes32 _subgraphDeploymentID, uint256 _tokens) private {
        require(
            isCurated(_subgraphDeploymentID),
            "SubgraphDeployment must be curated to collect fees"
        );

        // Collect new funds into reserve
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        curationPool.tokens = curationPool.tokens.add(_tokens);

        emit Collected(_subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Deposit Graph Tokens in exchange for shares of a curation pool.
     * @param _curator Address of the staking party
     * @param _subgraphDeploymentID SubgraphDeployment where the curator is staking tokens
     * @param _tokens Amount of Graph Tokens to stake
     */
    function _stake(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) private {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];

        // If it hasn't been curated before then initialize the curve
        if (!isCurated(_subgraphDeploymentID)) {
            require(_tokens >= minimumCurationStake, "Curation stake is below minimum required");

            // Initialize
            curationPool.reserveRatio = defaultReserveRatio;
        }

        // Update balances
        uint256 shares = _buyShares(_curator, _subgraphDeploymentID, _tokens);

        emit Staked(_curator, _subgraphDeploymentID, _tokens, shares);
    }

    /**
     * @dev Calculate the percentage for value in parts per million (PPM)
     * @param _ppm Parts per million
     * @param _value Value to calculate percentage of
     * @return Percentage of value
     */
    function percentageOf(uint256 _ppm, uint256 _value) private pure returns (uint256) {
        return _ppm.mul(_value).div(MAX_PPM);
    }
}
