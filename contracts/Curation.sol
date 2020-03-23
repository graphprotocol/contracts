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
        uint256 totalStake;
        uint256 totalShares;
    }

    struct SubgraphCurator {
        uint256 totalShares;
    }

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // -- State --

    // Default reserve ratio to configure curator shares bonding curve (for new subgraphs)
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public defaultReserveRatio;

    // Minimum amount allowed to be staked by Market Curators
    uint256 public minimumCurationStake;

    // Subgraphs mapping
    mapping(bytes32 => Subgraph) public subgraphs;

    // Subgraphs/Curators mapping
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
        uint256 totalStake
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

        // Underflow protection
        require(
            subgraphCurator.totalShares >= _shares,
            "Cannot unstake more shares than you own"
        );

        // Obtain the amount of tokens to refund based on returned shares
        uint256 tokensToRefund = convertSharesToStake(
            _shares,
            subgraph.totalStake,
            subgraph.totalShares,
            subgraph.reserveRatio
        );

        // Update subgraph balances
        subgraph.totalStake = subgraph.totalStake.sub(tokensToRefund);
        subgraph.totalShares = subgraph.totalShares.sub(_shares);

        // Update subgraph/curator balances
        subgraphCurator.totalShares = subgraphCurator.totalShares.sub(_shares);

        // Delete if left without stakes
        if (subgraph.totalStake == 0) {
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
            subgraph.totalStake
        );
    }

    /**
      * @dev Check if any Graph tokens are staked for a particular subgraph
      * @param _subgraphID <uint256> Subgraph ID to check if tokens are staked
      * @return <bool> True if the subgraph is curated
      */
    function isSubgraphCurated(bytes32 _subgraphID) public view returns (bool) {
        return subgraphs[_subgraphID].totalStake > 0;
    }

    /**
     * @dev Calculate number of shares that should be issued in return for
     *      staking of _purchaseAmount of tokens, along the given bonding curve
     * @param _purchaseTokens <uint256> - Amount of tokens being staked (purchase amount)
     * @param _currentTokens <uint256> - Total amount of tokens currently in reserves
     * @param _currentShares <uint256> - Total amount of current shares issued
     * @param _reserveRatio <uint256> - Desired reserve ratio to maintain (in PPM)
     * @return issuedShares <uint256> - Amount of additional shares issued given the above
     */
    function convertStakeToShares(
        uint256 _purchaseTokens,
        uint256 _currentTokens,
        uint256 _currentShares,
        uint256 _reserveRatio
    ) public view returns (uint256) {
        return
            calculatePurchaseReturn(
                _currentShares,
                _currentTokens,
                uint32(_reserveRatio),
                _purchaseTokens
            );
    }

    /**
     * @dev Calculate number of tokens that should be returned for the proportion
     *      of _returnedShares to _currentShares, along the given bonding curve
     * @param _returnedShares <uint256> - Amount of shares being returned
     * @param _currentTokens <uint256> - Total amount of tokens currently in reserves
     * @param _currentShares <uint256> - Total amount of current shares issued
     * @param _reserveRatio <uint256> - Desired reserve ratio to maintain (in PPM)
     * @return <uint256> - Amount of tokens to return given the above
     */
    function convertSharesToStake(
        uint256 _returnedShares,
        uint256 _currentTokens,
        uint256 _currentShares,
        uint256 _reserveRatio
    ) public view returns (uint256) {
        return
            calculateSaleReturn(
                _currentShares,
                _currentTokens,
                uint32(_reserveRatio),
                _returnedShares
            );
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
        subgraph.totalStake = subgraph.totalStake.add(_amount);

        emit SubgraphStakeUpdated(
            _subgraphID,
            subgraph.totalShares,
            subgraph.totalStake
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

            // Update subgraph balances
            // Note: The first share costs minimumCurationStake amount of tokens
            subgraph.reserveRatio = defaultReserveRatio;
            subgraph.totalStake = minimumCurationStake;
            subgraph.totalShares = 1;

            // Update subgraph/curator balances
            subgraphCurator.totalShares = 1;

            tokens = tokens.sub(minimumCurationStake);
        }

        // Process unallocated tokens
        if (tokens > 0) {
            // Obtain the amount of shares to buy with the amount of tokens to sell
            uint256 newShares = convertStakeToShares(
                tokens,
                subgraph.totalStake,
                subgraph.totalShares,
                subgraph.reserveRatio
            );

            // Update subgraph balances
            subgraph.totalStake = subgraph.totalStake.add(tokens);
            subgraph.totalShares = subgraph.totalShares.add(newShares);

            // Update subgraph/curator balances
            subgraphCurator.totalShares = subgraphCurator.totalShares.add(
                newShares
            );
        }

        emit CuratorStakeUpdated(
            _curator,
            _subgraphID,
            subgraphCurator.totalShares
        );
        emit SubgraphStakeUpdated(
            _subgraphID,
            subgraph.totalShares,
            subgraph.totalStake
        );
    }
}
