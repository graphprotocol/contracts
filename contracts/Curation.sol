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
        mapping(address => uint256) curatorShares;
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

    // Minimum amount allowed to be staked by Market Curators
    // This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationStake;

    // Total staked tokens across all subgraphs
    uint256 public totalTokens;

    // Subgraphs and curators mapping
    mapping(bytes32 => Subgraph) public subgraphs;

    // Address of a party that will distribute fees to subgraph reserves
    address public distributor;

    // Token used for staking
    GraphToken public token;

    // -- Events --

    event CuratorStakeUpdated(address indexed curator, bytes32 indexed subgraphID, uint256 shares);
    event SubgraphStakeUpdated(bytes32 indexed subgraphID, uint256 shares, uint256 tokens);

    /**
     * @dev Contract Constructor
     * @param _governor Owner address of this contract
     * @param _token Address of the Graph Protocol token
     * @param _distributor Address of distributor of fees that goes to reserve funds
     * @param _defaultReserveRatio Address of the staking contract used for slashing
     * @param _minimumCurationStake Percent of stake the fisherman gets on slashing (in PPM)
     */
    constructor(
        address _governor,
        address _token,
        address _distributor,
        uint256 _defaultReserveRatio,
        uint256 _minimumCurationStake
    ) public Governed(_governor) {
        token = GraphToken(_token);
        _setDistributor(_distributor);
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
        _setDistributor(_distributor);
    }

    /**
     * @dev Set the address of party in charge of fee distributions into reserves
     * @param _distributor Address of the party doing fee distributions
     */
    function _setDistributor(address _distributor) private {
        require(_distributor != address(0), "Distributor must be set");
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
     * @return True token transfer is processed
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
            collect(subgraphID, _value);
            return true;
        }

        // Any other source address means they are staking
        stake(_from, subgraphID, _value);
        return true;
    }

    /**
     * @dev Return any amount of shares to get tokens back (above the minimum)
     * @notice Unstake _share shares from the _subgraphID subgraph
     * @param _subgraphID Subgraph ID the Curator is returning shares for
     * @param _shares Amount of shares to return
     */
    function unstake(bytes32 _subgraphID, uint256 _shares) external {
        address curator = msg.sender;
        Subgraph storage subgraph = subgraphs[_subgraphID];

        require(_shares > 0, "Cannot unstake zero shares");
        require(
            subgraph.curatorShares[curator] >= _shares,
            "Cannot unstake more shares than you own"
        );

        // Update balance and get the amount of tokens to refund based on returned shares
        uint256 tokensToRefund = _sellShares(curator, _subgraphID, _shares);

        // Ensure we are not under minimum required stake
        require(
            subgraph.tokens >= minimumCurationStake || subgraph.tokens == 0,
            "Cannot unstake below minimum required stake for subgraph"
        );

        // Delete if left without stakes
        if (subgraph.tokens == 0) {
            delete subgraphs[_subgraphID];
        }

        // Return the tokens to the curator
        require(token.transfer(curator, tokensToRefund), "Error sending curator tokens");

        emit CuratorStakeUpdated(curator, _subgraphID, subgraph.curatorShares[curator]);
        emit SubgraphStakeUpdated(_subgraphID, subgraph.shares, subgraph.tokens);
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
    function subgraphTokensToShares(bytes32 _subgraphID, uint256 _tokens)
        public
        view
        returns (uint256)
    {
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
    function subgraphSharesToTokens(bytes32 _subgraphID, uint256 _shares)
        public
        view
        returns (uint256)
    {
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
        internal
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphID];
        uint256 shares = subgraphTokensToShares(_subgraphID, _tokens);

        // Update tokens
        subgraph.tokens = subgraph.tokens.add(_tokens);

        // Update shares
        subgraph.shares = subgraph.shares.add(shares);
        subgraph.curatorShares[_curator] = subgraph.curatorShares[_curator].add(shares);

        // Update global balance
        totalTokens = totalTokens.add(_tokens);

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
        internal
        returns (uint256)
    {
        Subgraph storage subgraph = subgraphs[_subgraphID];
        uint256 tokens = subgraphSharesToTokens(_subgraphID, _shares);

        // Update tokens
        subgraph.tokens = subgraph.tokens.sub(tokens);

        // Update shares
        subgraph.shares = subgraph.shares.sub(_shares);
        subgraph.curatorShares[_curator] = subgraph.curatorShares[_curator].sub(_shares);

        // Update global balance
        totalTokens = totalTokens.sub(tokens);

        return tokens;
    }

    /**
     * @dev Update balances after buy of shares and deposit of tokens
     * @param _curator <address> - Curator
     * @param _subgraphID <bytes32> - Subgraph
     * @param _tokens <uint256> - Amount of tokens
     * @param _shares <uint256> - Amount of shares
     */
    function increaseBalance(
        address _curator,
        bytes32 _subgraphID,
        uint256 _tokens,
        uint256 _shares
    ) internal {
        // Update subgraph balance
        Subgraph storage subgraph = subgraphs[_subgraphID];
        subgraph.tokens = subgraph.tokens.add(_tokens);
        subgraph.shares = subgraph.shares.add(_shares);
        subgraph.curatorShares[_curator] = subgraph.curatorShares[_curator].add(_shares);

        // Update global balance
        totalTokens = totalTokens.add(_tokens);
    }

    /**
     * @dev Update balances after sell of shares and return of tokens
     * @param _curator <address> - Curator
     * @param _subgraphID <bytes32> - Subgraph
     * @param _tokens <uint256> - Amount of tokens
     * @param _shares <uint256> - Amount of shares
     */
    function decreaseBalance(
        address _curator,
        bytes32 _subgraphID,
        uint256 _tokens,
        uint256 _shares
    ) internal {
        // Update subgraph balance
        Subgraph storage subgraph = subgraphs[_subgraphID];
        subgraph.tokens = subgraph.tokens.sub(_tokens);
        subgraph.shares = subgraph.shares.sub(_shares);
        subgraph.curatorShares[_curator] = subgraph.curatorShares[_curator].sub(_shares);

        // Update global balance
        totalTokens = totalTokens.sub(_tokens);
    }

    /**
     * @dev Assign Graph Tokens received from distributor to the subgraph reserve
     * @param _subgraphID Subgraph where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function collect(bytes32 _subgraphID, uint256 _tokens) private {
        require(isSubgraphCurated(_subgraphID), "Subgraph must be curated to collect fees");

        // Collect new funds to reserve
        Subgraph storage subgraph = subgraphs[_subgraphID];
        subgraph.tokens = subgraph.tokens.add(_tokens);

        // Update global tokens balance
        totalTokens = totalTokens.add(_tokens);

        emit SubgraphStakeUpdated(_subgraphID, subgraph.shares, subgraph.tokens);
    }

    /**
     * @dev Stake Graph Tokens for Market Curation by subgraphID
     * @param _subgraphID Subgraph ID the Curator is staking Graph Tokens for
     * @param _curator Address of Staking party
     * @param _tokens Amount of Graph Tokens to be staked
     */
    function stake(address _curator, bytes32 _subgraphID, uint256 _tokens) private {
        uint256 tokens = _tokens;
        Subgraph storage subgraph = subgraphs[_subgraphID];

        // If this subgraph hasn't been curated before then initialize the curve
        if (!isSubgraphCurated(_subgraphID)) {
            require(tokens >= minimumCurationStake, "Curation stake is below minimum required");

            // Initialize subgraph
            subgraph.reserveRatio = defaultReserveRatio;
        }

        // Update subgraph balances
        _buyShares(_curator, _subgraphID, tokens);

        emit CuratorStakeUpdated(_curator, _subgraphID, subgraph.curatorShares[_curator]);
        emit SubgraphStakeUpdated(_subgraphID, subgraph.shares, subgraph.tokens);
    }
}
