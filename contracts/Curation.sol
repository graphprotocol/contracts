pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Curation contract
 * @notice Allows Curators to signal Subgraphs that are relevant for indexers and earn fees from the Query Market
 */

import "./Governed.sol";
import "./GraphToken.sol";
import "./bancor/BancorFormula.sol";
import "./bytes/BytesLib.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract Curation is Governed, BancorFormula {
    using BytesLib for bytes;
    using SafeMath for uint256;

    // -- Curation --

    struct Subgraph {
        uint256 reserveRatio; // Ratio for the bonding curve
        uint256 tokens; // Tokens that constitute the subgraph reserve
        uint256 shares; // Shares issued for this subgraph
        mapping(address => uint256) curatorShares; // Mapping of curator => shares
    }

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // Amount of shares you get with your minimum token stake
    uint256 private constant SHARES_PER_MINIMUM_STAKE = 1;

    // -- State --

    // Default reserve ratio to configure curator shares bonding curve (for new subgraphs)
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public defaultReserveRatio;

    // Minimum amount allowed to be staked by curators
    // This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationStake;

    // Mapping of subgraphID => Subgraph
    mapping(bytes32 => Subgraph) public subgraphs;

    // Address of a party that will distribute fees to subgraph reserves
    address public distributor;

    // Token used for staking
    GraphToken public token;

    // -- Events --

    event Staked(
        address indexed curator,
        bytes32 indexed subgraphID,
        uint256 tokens,
        uint256 shares
    );

    event Redeemed(
        address indexed curator,
        bytes32 indexed subgraphID,
        uint256 tokens,
        uint256 shares
    );

    event Rewarded(bytes32 indexed subgraphID, uint256 tokens);

    /**
     * @dev Contract Constructor
     * @param _governor Owner address of this contract
     * @param _token Address of the Graph Protocol token
     * @param _defaultReserveRatio Address of the staking contract used for slashing
     * @param _minimumCurationStake Percent of stake the fisherman gets on slashing (in PPM)
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
     * @dev Set the default reserve ratio percentage for new subgraphs
     * @notice Update the default reserver ratio to `_defaultReserveRatio`
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint256 _defaultReserveRatio) external onlyGovernor {
        _setDefaultReserveRatio(_defaultReserveRatio);
    }

    /**
     * @dev Set the default reserve ratio percentage for new subgraphs
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
    }

    /**
     * @dev Set the address of party in charge of fee distributions into reserves
     * @notice Update the distributor address to `_distributor`
     * @param _distributor Address of the party doing fee distributions
     */
    function setDistributor(address _distributor) external onlyGovernor {
        distributor = _distributor;
    }

    /**
     * @dev Set the minimum stake amount for curators
     * @notice Update the minimum stake amount to `_minimumCurationStake`
     * @param _minimumCurationStake Minimum amount of tokens required stake
     */
    function setMinimumCurationStake(uint256 _minimumCurationStake) external onlyGovernor {
        _setMinimumCurationStake(_minimumCurationStake);
    }

    /**
     * @dev Set the minimum stake amount for curators
     * @param _minimumCurationStake Minimum amount of tokens required stake
     */
    function _setMinimumCurationStake(uint256 _minimumCurationStake) private {
        require(_minimumCurationStake > 0, "Minimum curation stake cannot be 0");
        minimumCurationStake = _minimumCurationStake;
    }

    /**
     * @dev Accept tokens
     * @notice Receive Graph tokens
     * @param _from Token holder's address
     * @param _value Amount of Graph Tokens
     * @param _data Extra data payload
     * @return true if token transfer is processed
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token), "Caller is not the GRT token contract");

        // Decode subgraphID
        bytes32 subgraphID = _data.slice(0, 32).toBytes32(0);

        // Transfers from distributor means we are assigning fees to reserves
        if (_from == distributor) {
            _collect(subgraphID, _value);
            return true;
        }

        // Any other source address means they are staking tokens for shares
        _stake(_from, subgraphID, _value);
        return true;
    }

    /**
     * @dev Return an amount of shares to get tokens back
     * @notice Redeem _shares from the subgraph with _subgraphID
     * @param _subgraphID Subgraph ID the Curator is returning shares for
     * @param _shares Amount of shares to return
     */
    function redeem(bytes32 _subgraphID, uint256 _shares) external {
        address curator = msg.sender;
        Subgraph storage subgraph = subgraphs[_subgraphID];

        require(_shares > 0, "Cannot redeem zero shares");
        require(
            subgraph.curatorShares[curator] >= _shares,
            "Cannot redeem more shares than you own"
        );

        // Update balance and get the amount of tokens to refund based on returned shares
        uint256 tokens = _sellShares(curator, _subgraphID, _shares);

        // If all shares redeemed delete subgraph
        if (subgraph.shares == 0) {
            delete subgraphs[_subgraphID];
        }

        // Return the tokens to the curator
        require(token.transfer(curator, tokens), "Error sending curator tokens");

        emit Redeemed(curator, _subgraphID, tokens, _shares);
    }

    /**
     * @dev Check if any Graph tokens are staked for a particular subgraph
     * @param _subgraphID Subgraph ID to check if tokens are staked
     * @return True if the subgraph is curated
     */
    function isSubgraphCurated(bytes32 _subgraphID) public view returns (bool) {
        return subgraphs[_subgraphID].tokens > 0;
    }

    /**
     * @dev Get the number of shares a curator has on a particular subgraph
     * @param _curator Curator owning the shares
     * @param _subgraphID Subgraph of issued shares
     * @return Number of subgraph shares issued for a curator
     */
    function getCuratorShares(address _curator, bytes32 _subgraphID) public view returns (uint256) {
        return subgraphs[_subgraphID].curatorShares[_curator];
    }

    /**
     * @dev Calculate number of subgraph shares that can be bought with a number of tokens
     * @param _subgraphID Subgraph ID from where to buy shares
     * @param _tokens Amount of tokens used to buy shares
     * @return Amount of shares that can be bought
     */
    function tokensToShares(bytes32 _subgraphID, uint256 _tokens) public view returns (uint256) {
        // Handle initialization of bonding curve
        uint256 tokens = _tokens;
        uint256 shares = 0;
        Subgraph memory subgraph = subgraphs[_subgraphID];
        if (subgraph.tokens == 0) {
            subgraph = Subgraph(
                defaultReserveRatio,
                minimumCurationStake,
                SHARES_PER_MINIMUM_STAKE
            );
            tokens = tokens.sub(subgraph.tokens);
            shares = subgraph.shares;
        }

        return
            calculatePurchaseReturn(
                subgraph.shares,
                subgraph.tokens,
                uint32(subgraph.reserveRatio),
                tokens
            ) + shares;
    }

    /**
     * @dev Calculate number of tokens to get when selling subgraph shares
     * @param _subgraphID Subgraph ID from where to sell shares
     * @param _shares Amount of shares to sell
     * @return Amount of tokens to get after selling shares
     */
    function sharesToTokens(bytes32 _subgraphID, uint256 _shares) public view returns (uint256) {
        Subgraph memory subgraph = subgraphs[_subgraphID];
        require(subgraph.tokens > 0, "Subgraph must be curated to perform calculations");
        require(
            subgraph.shares >= _shares,
            "Shares must be above or equal to total shares issued for the subgraph"
        );
        return
            calculateSaleReturn(
                subgraph.shares,
                subgraph.tokens,
                uint32(subgraph.reserveRatio),
                _shares
            );
    }

    /**
     * @dev Update balances after buy of shares and deposit of tokens
     * @param _curator Curator
     * @param _subgraphID Subgraph
     * @param _tokens Amount of tokens
     * @return Number of shares bought
     */
    function _buyShares(address _curator, bytes32 _subgraphID, uint256 _tokens)
        private
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphID];
        uint256 shares = tokensToShares(_subgraphID, _tokens);

        // Update tokens
        subgraph.tokens = subgraph.tokens.add(_tokens);

        // Update shares
        subgraph.shares = subgraph.shares.add(shares);
        subgraph.curatorShares[_curator] = subgraph.curatorShares[_curator].add(shares);

        return shares;
    }

    /**
     * @dev Update balances after sell of shares and return of tokens
     * @param _curator Curator
     * @param _subgraphID Subgraph
     * @param _shares Amount of shares
     * @return Number of tokens received
     */
    function _sellShares(address _curator, bytes32 _subgraphID, uint256 _shares)
        private
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphID];
        uint256 tokens = sharesToTokens(_subgraphID, _shares);

        // Update tokens
        subgraph.tokens = subgraph.tokens.sub(tokens);

        // Update shares
        subgraph.shares = subgraph.shares.sub(_shares);
        subgraph.curatorShares[_curator] = subgraph.curatorShares[_curator].sub(_shares);

        return tokens;
    }

    /**
     * @dev Assign Graph Tokens received from distributor to the subgraph reserve
     * @param _subgraphID Subgraph where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function _collect(bytes32 _subgraphID, uint256 _tokens) private {
        require(isSubgraphCurated(_subgraphID), "Subgraph must be curated to collect fees");

        // Collect new funds to into a subgraph reserve
        Subgraph storage subgraph = subgraphs[_subgraphID];
        subgraph.tokens = subgraph.tokens.add(_tokens);

        emit Rewarded(_subgraphID, _tokens);
    }

    /**
     * @dev Deposit Graph Tokens in exchange for shares of a subgraph
     * @param _subgraphID Subgraph ID where the curator is staking Graph Tokens
     * @param _curator Address of staking party
     * @param _tokens Amount of Graph Tokens to stake
     */
    function _stake(address _curator, bytes32 _subgraphID, uint256 _tokens) private {
        Subgraph storage subgraph = subgraphs[_subgraphID];

        // If this subgraph hasn't been curated before then initialize the curve
        if (!isSubgraphCurated(_subgraphID)) {
            require(_tokens >= minimumCurationStake, "Curation stake is below minimum required");

            // Initialize subgraph
            subgraph.reserveRatio = defaultReserveRatio;
        }

        // Update subgraph balances
        uint256 shares = _buyShares(_curator, _subgraphID, _tokens);

        emit Staked(_curator, _subgraphID, _tokens, shares);
    }
}
