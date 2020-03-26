pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Curation contract
 * @notice Allows Curators to signal Subgraphs that are relevant for indexers and earn fees from the Query Market.
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
        uint256 reserveRatio;
        uint256 totalTokens;
        uint256 totalShares;
    }

    struct SubgraphCurator {
        uint256 totalShares;
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
    mapping(bytes32 => mapping(address => SubgraphCurator)) public subgraphCurators;

    // Address of a party that will distribute fees to subgraph reserves
    address public distributor;

    // Token used for staking
    GraphToken public token;

    // -- Events --

    event CuratorStakeUpdated(
        address indexed curator,
        bytes32 indexed subgraphID,
        uint256 totalShares
    );

    event SubgraphStakeUpdated(
        bytes32 indexed subgraphID,
        uint256 totalShares,
        uint256 totalTokens
    );

    /**
     * @dev Contract Constructor
     * @param _governor <address> - Owner address of this contract
     * @param _token <address> - Address of the Graph Protocol token
     * @param _distributor <address> - Address of distributor of fees that goes to reserve funds
     * @param _defaultReserveRatio <uint256> - Address of the staking contract used for slashing
     * @param _minimumCurationStake <uint256> - Percent of stake the fisherman gets on slashing (in PPM)
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
     * @param _defaultReserveRatio <uint256> - Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint256 _defaultReserveRatio)
        external
        onlyGovernance
    {
        _setDefaultReserveRatio(_defaultReserveRatio);
    }

    /**
     * @dev Set the default reserve ratio percentage for new subgraphs
     * @param _defaultReserveRatio <uint256> - Reserve ratio (in PPM)
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
     * @param _distributor <address> - Address of the party doing fee distributions
     */
    function setDistributor(address _distributor) external onlyGovernance {
        _setDistributor(_distributor);
    }

    /**
     * @dev Set the address of party in charge of fee distributions into reserves
     * @param _distributor <address> - Address of the party doing fee distributions
     */
    function _setDistributor(address _distributor) private {
        require(_distributor != address(0), "Distributor must be set");
        distributor = _distributor;
    }

    /**
     * @dev Set the minimum stake amount for curators
     * @notice Update the minimum stake amount to `_minimumCurationStake`
     * @param _minimumCurationStake <uint256> - Minimum amount of tokens required stake
     */
    function setMinimumCurationStake(uint256 _minimumCurationStake)
        external
        onlyGovernance
    {
        _setMinimumCurationStake(_minimumCurationStake);
    }

    /**
     * @dev Set the minimum stake amount for curators
     * @param _minimumCurationStake <uint256> - Minimum amount of tokens required stake
     */
    function _setMinimumCurationStake(uint256 _minimumCurationStake) private {
        require(
            _minimumCurationStake > 0,
            "Minimum curation stake cannot be 0"
        );
        minimumCurationStake = _minimumCurationStake;
    }

    /**
     * @dev Accept tokens
     * @notice Receive Graph tokens
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens
     * @param _data <bytes> - Extra data payload
     * @return <bool> True token transfer is processed
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(
            msg.sender == address(token),
            "Caller is not the GRT token contract"
        );

        // Decode subgraphID
        bytes32 subgraphID = _data.slice(0, 32).toBytes32(0);

        // Transfers from distributor means we are assigning fees to reserves
        if (_from == distributor) {
            collect(subgraphID, _value);
            return true;
        }

        // Any other source address means they are staking
        stake(subgraphID, _from, _value);
        return true;
    }

    /**
     * @dev Return any amount of shares to get tokens back (above the minimum)
     * @notice Unstake _share shares from the _subgraphID subgraph
     * @param _subgraphID <bytes32> - Subgraph ID the Curator is returning shares for
     * @param _shares <uint256> - Amount of shares to return
     */
    function unstake(bytes32 _subgraphID, uint256 _shares) external {
        address curator = msg.sender;
        Subgraph storage subgraph = subgraphs[_subgraphID];
        SubgraphCurator storage subgraphCurator = subgraphCurators[_subgraphID][curator];

        require(_shares > 0, "Cannot unstake zero shares");
        require(
            subgraphCurator.totalShares >= _shares,
            "Cannot unstake more shares than you own"
        );

        // Obtain the amount of tokens to refund based on returned shares
        uint256 tokensToRefund = subgraphSharesToTokens(_subgraphID, _shares);
        uint256 tokensLeft = subgraph.totalTokens.sub(tokensToRefund);

        // Ensure we are not under minimum required stake
        require(
            tokensLeft >= minimumCurationStake || tokensLeft == 0,
            "Cannot unstake below minimum required stake for subgraph"
        );

        // Update subgraph balances
        subgraph.totalTokens = tokensLeft;
        subgraph.totalShares = subgraph.totalShares.sub(_shares);

        // Update subgraph/curator balances
        subgraphCurator.totalShares = subgraphCurator.totalShares.sub(_shares);

        // Update global tokens balance
        totalTokens = totalTokens.sub(tokensToRefund);

        // Delete if left without stakes
        if (subgraph.totalTokens == 0) {
            delete subgraphs[_subgraphID];
        }
        if (subgraphCurator.totalShares == 0) {
            delete subgraphCurators[_subgraphID][curator];
        }

        // Return the tokens to the curator
        require(
            token.transfer(curator, tokensToRefund),
            "Error sending curator tokens"
        );

        emit CuratorStakeUpdated(
            curator,
            _subgraphID,
            subgraphCurator.totalShares
        );
        emit SubgraphStakeUpdated(
            _subgraphID,
            subgraph.totalShares,
            subgraph.totalTokens
        );
    }

    /**
      * @dev Check if any Graph tokens are staked for a particular subgraph
      * @param _subgraphID <uint256> Subgraph ID to check if tokens are staked
      * @return <bool> True if the subgraph is curated
      */
    function isSubgraphCurated(bytes32 _subgraphID) public view returns (bool) {
        return subgraphs[_subgraphID].totalTokens > 0;
    }

    /**
      * @dev Calculate number of subgraph shares that can be bought with a number of tokens
      * @param _subgraphID <bytes32> Subgraph ID from where to buy shares
      * @param _tokens <uint256> Amount of tokens used to buy shares
      * @return <uint256> Amount of shares that can be bought
      */
    function subgraphTokensToShares(bytes32 _subgraphID, uint256 _tokens)
        public
        view
        returns (uint256)
    {
        // handle initialization of bonding curve
        uint256 shares = 0;
        Subgraph memory subgraph = subgraphs[_subgraphID];
        if (subgraph.totalTokens == 0) {
            subgraph = getDefaultSubgraph();
            shares = 1;
        }

        return
            calculatePurchaseReturn(
                subgraph.totalShares,
                subgraph.totalTokens,
                uint32(subgraph.reserveRatio),
                _tokens
            ) +
            shares;
    }

    /**
      * @dev Calculate number of tokens to get when selling subgraph shares
      * @param _subgraphID <bytes32> Subgraph ID from where to sell shares
      * @param _shares <uint256> Amount of shares to sell
      * @return <uint256> Amount of tokens to get after selling shares
      */
    function subgraphSharesToTokens(bytes32 _subgraphID, uint256 _shares)
        public
        view
        returns (uint256)
    {
        Subgraph memory subgraph = subgraphs[_subgraphID];
        require(
            subgraph.totalTokens > 0,
            "Subgraph must be curated to perform calculations"
        );
        require(
            subgraph.totalShares >= _shares,
            "Shares must be above or equal to total shares issued for the subgraph"
        );
        return
            calculateSaleReturn(
                subgraph.totalShares,
                subgraph.totalTokens,
                uint32(subgraph.reserveRatio),
                _shares
            );
    }

    /**
     * @dev Get a sugbraph using default initial values
     * @return <Subgraph> An initialized subgraph
     */
    function getDefaultSubgraph() private view returns (Subgraph memory) {
        Subgraph memory subgraph = Subgraph(
            defaultReserveRatio,
            minimumCurationStake,
            SHARES_PER_MINIMUM_STAKE
        );
        return subgraph;
    }

    /**
     * @dev Assign Graph Tokens received from distributor to the subgraph reserve
     * @param _subgraphID <bytes32> - Subgraph where funds should be allocated as reserves
     * @param _amount <uint256> - Amount of Graph Tokens to add to reserves
     */
    function collect(bytes32 _subgraphID, uint256 _amount) private {
        require(
            isSubgraphCurated(_subgraphID),
            "Subgraph must be curated to collect fees"
        );

        // Collect new funds to reserve
        Subgraph storage subgraph = subgraphs[_subgraphID];
        subgraph.totalTokens = subgraph.totalTokens.add(_amount);

        // Update global tokens balance
        totalTokens = totalTokens.add(_amount);

        emit SubgraphStakeUpdated(
            _subgraphID,
            subgraph.totalShares,
            subgraph.totalTokens
        );
    }

    /**
     * @dev Stake Graph Tokens for Market Curation by subgraphID
     * @param _subgraphID <bytes32> - Subgraph ID the Curator is staking Graph Tokens for
     * @param _curator <address> - Address of Staking party
     * @param _amount <uint256> - Amount of Graph Tokens to be staked
     */
    function stake(bytes32 _subgraphID, address _curator, uint256 _amount)
        private
    {
        uint256 tokens = _amount;
        Subgraph storage subgraph = subgraphs[_subgraphID];
        SubgraphCurator storage subgraphCurator = subgraphCurators[_subgraphID][_curator];

        // If this subgraph hasn't been curated before then initialize the curve
        // Sets the initial slope for the curve, controlled by minimumCurationStake
        if (!isSubgraphCurated(_subgraphID)) {
            // Additional pre-condition check
            require(
                tokens >= minimumCurationStake,
                "Curation stake is below minimum required"
            );

            // Initialize subgraph
            // Note: The first share costs minimumCurationStake amount of tokens
            subgraphs[_subgraphID] = getDefaultSubgraph();

            // Update subgraph/curator balance
            subgraphCurator.totalShares = SHARES_PER_MINIMUM_STAKE;

            // Update tokens used for stake
            tokens = tokens.sub(minimumCurationStake);
        }

        // Process unallocated tokens
        if (tokens > 0) {
            // Obtain the amount of shares to buy with the amount of tokens to sell
            uint256 newShares = subgraphTokensToShares(_subgraphID, tokens);

            // Update subgraph balances
            subgraph.totalTokens = subgraph.totalTokens.add(tokens);
            subgraph.totalShares = subgraph.totalShares.add(newShares);

            // Update subgraph/curator balances
            subgraphCurator.totalShares = subgraphCurator.totalShares.add(
                newShares
            );
        }

        // Update global tokens balance
        totalTokens = totalTokens.add(_amount);

        emit CuratorStakeUpdated(
            _curator,
            _subgraphID,
            subgraphCurator.totalShares
        );
        emit SubgraphStakeUpdated(
            _subgraphID,
            subgraph.totalShares,
            subgraph.totalTokens
        );
    }
}
