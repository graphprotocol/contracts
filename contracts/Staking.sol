pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Staking contract
 *
 */

import "./Governed.sol";
import "./GraphToken.sol";
import "./bytes/BytesLib.sol";


contract Staking is Governed {
    using BytesLib for bytes;

    event IndexNodeStaked(
        address indexed staker,
        uint256 amountStaked,
        bytes32 subgraphID,
        uint256 subgraphTotalIndexingStake
    );

    event IndexNodeBeginLogout(
        address indexed staker,
        bytes32 subgraphID,
        uint256 unstakedAmount,
        uint256 fees
    );

    event IndexNodeFinalizeLogout(address indexed staker, bytes32 subgraphID);

    event SlasherUpdated(
        address indexed caller,
        address indexed slasher,
        bool enabled
    );

    struct IndexNode {
        uint256 amountStaked;
        uint256 feesAccrued;
        uint256 logoutStarted;
        uint256 lockedTokens;
    }

    struct Subgraph {
        uint256 totalIndexingStake;
        uint256 totalIndexers;
    }

    enum TokenReceiptAction { Staking, Settlement }

    // Minimum amount allowed to be staked by Indexing Nodes
    uint256 public minimumIndexingStakingAmount;

    // Maximum number of Indexing Nodes staked higher than stake to consider
    uint256 public maximumIndexers;

    // Amount of seconds to wait until indexer can finish stake logout
    // @dev Thawing Period allows disputes to be processed during logout
    uint256 public thawingPeriod;

    // Mapping subgraphId to list of addresses to Indexing Nodes
    mapping(bytes32 => mapping(address => IndexNode)) public indexNodes;

    // A dynamic array of index node addresses that bootstrap the graph subgraph
    // Note: The graph subgraph bootstraps the network. It has no way to retrieve
    //       the list of all indexers at the start of indexing. The indexingNodes
    //       mapping can be retrieved for all other subgraphs, since they can
    //       depend on the existing graph subgraph. Therefore, a single dynamic
    //       array exists as its own variable graphIndexingNodeAddresses, along with the
    //       graphSubgraphID public variable. The graphIndexing nodes are still stored
    //       in indexingNodes, but with this array, and the graphSubgraphID as public
    //       variables, the bootstrap indexing nodes can be retrieved without a subgraph.

    // TODO - potentially implement a upper limit, say 100 indexers, for simplification
    address[] public graphIndexNodeAddresses;

    // The graph subgraph ID
    bytes32 public graphSubgraphID;

    // Subgraphs mapping
    mapping(bytes32 => Subgraph) public subgraphs;

    // List of addresses allowed to slash
    mapping(address => bool) public slashers;

    // Related contracts
    GraphToken public token;

    // @dev 100% in parts per million.
    uint256 private constant MAX_PPM = 1000000;

    // @dev 1 basis point (0.01%) is 100 parts per million (PPM).
    uint256 private constant BASIS_PT = 100;

    modifier onlySlasher {
        require(slashers[msg.sender] == true, "Caller is not a Slasher");
        _;
    }

    /**
     * @dev Staking Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     * @param _token <address> - Address of the Graph Protocol token
     */
    constructor(
        address _governor,
        uint256 _minimumIndexingStakingAmount,
        uint256 _maximumIndexers,
        uint256 _thawingPeriod,
        address _token
    ) public Governed(_governor) {
        // Governance Parameter Defaults
        minimumIndexingStakingAmount = _minimumIndexingStakingAmount; // @imp i03
        maximumIndexers = _maximumIndexers;
        thawingPeriod = _thawingPeriod;
        token = GraphToken(_token); // Question - do we need a function to upgrade this?
    }

    function addSlasher(address _slasher) external onlyGovernor {
        slashers[_slasher] = true;
        emit SlasherUpdated(msg.sender, _slasher, true);
    }

    function removeSlasher(address _slasher) external onlyGovernor {
        slashers[_slasher] = false;
        emit SlasherUpdated(msg.sender, _slasher, false);
    }

    /**
     * @dev Set the Minimum Staking Amount for Indexing Nodes
     * @param _minimumIndexingStakingAmount <uint256> - Minimum amount allowed to be staked
     * for Indexing Nodes
     */
    function setMinimumIndexingStakingAmount(
        uint256 _minimumIndexingStakingAmount
    ) external onlyGovernor returns (bool success) {
        minimumIndexingStakingAmount = _minimumIndexingStakingAmount; // @imp i03
        return true;
    }

    /**
     * @dev Set the maximum number of Indexing Nodes
     * @param _maximumIndexers <uint256> - Maximum number of Indexing Nodes allowed
     */
    function setMaximumIndexers(uint256 _maximumIndexers)
        external
        onlyGovernor
        returns (bool success)
    {
        maximumIndexers = _maximumIndexers;
        return true;
    }

    /**
     * @dev Set the thawing period for indexer logout
     * @param _thawingPeriod <uint256> - Number of seconds for thawing period
     */
    function updateThawingPeriod(uint256 _thawingPeriod) external onlyGovernor {
        thawingPeriod = _thawingPeriod;
    }

    function removeGraphIndexNode(address _indexNode) private returns (bool) {
        (bool found, uint256 userIndex) = findGraphIndexerIndex(_indexNode);
        if (found) {
            delete graphIndexNodeAddresses[userIndex];
            return true;
        }
        return false;
    }

    function getIndexNodeStake(bytes32 _subgraphId, address _indexNode)
        public
        view
        returns (uint256)
    {
        return indexNodes[_subgraphId][_indexNode].amountStaked;
    }

    function slash(
        bytes32 _subgraphId,
        address _indexNode,
        uint256 _reward,
        address _beneficiary
    ) external onlySlasher {
        require(
            _beneficiary != address(0),
            "Beneficiary must not be an empty address"
        );
        require(_reward > 0, "Slashing reward must be greater than 0");

        // Get indexer to be slashed


            IndexNode memory _slashedIndexNode
         = indexNodes[_subgraphId][_indexNode];

        // Remove indexer from the stakes
        delete indexNodes[_subgraphId][_indexNode]; // Re-entrancy protection

        // Indexer needs to exist and have stakes
        require(
            _slashedIndexNode.amountStaked > 0,
            "Indexer has no stake on the subgraph"
        );

        // Handle special case for bootstrap nodes
        if (_subgraphId == graphSubgraphID) {
            require(
                removeGraphIndexNode(_indexNode),
                "Bootstrap indexer not found"
            );
        }

        // Remove Indexing Node for subgraph
        subgraphs[_subgraphId].totalIndexingStake -= _slashedIndexNode
            .amountStaked;
        subgraphs[_subgraphId].totalIndexers -= 1;

        // Burn index node stake and fees setting apart a reward for the beneficiary
        uint256 tokensToBurn = (_slashedIndexNode.amountStaked - _reward) +
            _slashedIndexNode.feesAccrued;
        token.burn(tokensToBurn);

        // Give the beneficiary a reward for the slashing
        require(
            token.transfer(_beneficiary, _reward),
            "Error sending dispute deposit"
        );

        emit IndexNodeBeginLogout(
            _indexNode,
            _subgraphId,
            _slashedIndexNode.amountStaked,
            _slashedIndexNode.feesAccrued
        );
        emit IndexNodeFinalizeLogout(_indexNode, _subgraphId);
    }

    /**
     * @dev Set the graph subgraph ID
     * @param _subgraphID <bytes32> - The subgraph ID of the bootstrapping subgraph ID
     * @param _newIndexers <Array<address>> - Array of new indexers that have coordinated outside
     *        of the protocol, and pre-index the new subgraph before the switch happens
     */
    // TODO - Need to add in a check to make sure the indexers are already staked, i.e. they
    // TODO - exist in indexNodes for this subgraph (60% sure we need this...)
    function setGraphSubgraphID(
        bytes32 _subgraphID,
        address[] calldata _newIndexers
    ) external onlyGovernor returns (bool success) {
        graphSubgraphID = _subgraphID;
        graphIndexNodeAddresses = _newIndexers;
        return true;
    }

    /**
     * @dev Get the number of graph indexing nodes in the dynamic array
     */
    function numberOfGraphIndexNodeAddresses()
        public
        view
        returns (uint256 count)
    {
        return graphIndexNodeAddresses.length;
    }

    /**
     * @dev Accept tokens and handle staking registration functions
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool success)
    {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token));

        // Process _data to figure out the action to take (and which subgraph is involved)
        require(_data.length >= 1 + 32);
        // Must be at least 33 bytes (Header)
        TokenReceiptAction option = TokenReceiptAction(
            _data.slice(0, 1).toUint8(0)
        );
        bytes32 _subgraphId = _data.slice(1, 32).toBytes32(0);
        // In subgraph factory, not necessary

        if (option == TokenReceiptAction.Staking) {
            stakeForIndexing(_subgraphId, _from, _value);
        } else if (option == TokenReceiptAction.Settlement) {
            require(_data.length >= 33 + 20);
            // Header + _indexNode
            // address _indexNode = _data.slice(65, 20).toAddress(0);
            // distributeChannelFees(_subgraphId, _indexNode, _value);
        } else {
            revert("Token received option must be 0 or 1");
        }
        success = true;
    }

    /**
     * @dev Stake Graph Tokens for Indexing Node data retrieval by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node is staking Graph Tokens for
     * @param _indexer <address> - Address of Staking party
     * @param _value <uint256> - Amount of Graph Tokens to be staked
     */
    function stakeForIndexing(
        bytes32 _subgraphId,
        address _indexer,
        uint256 _value
    ) private {
        // If we are dealing with the graph subgraph bootstrap index nodes
        if (_subgraphId == graphSubgraphID) {
            (bool found, ) = findGraphIndexerIndex(_indexer);
            // If the user was never found, we must push them into the array
            if (found == false) {
                graphIndexNodeAddresses.push(_indexer);
            }
        }
        require(indexNodes[_subgraphId][_indexer].logoutStarted == 0);
        require(
            indexNodes[_subgraphId][_indexer].amountStaked + _value >=
                minimumIndexingStakingAmount
        ); // @imp i02
        if (indexNodes[_subgraphId][_indexer].amountStaked == 0)
            subgraphs[_subgraphId].totalIndexers += 1; // has not staked before
        indexNodes[_subgraphId][_indexer].amountStaked += _value;
        subgraphs[_subgraphId].totalIndexingStake += _value;

        emit IndexNodeStaked(
            _indexer,
            indexNodes[_subgraphId][_indexer].amountStaked,
            _subgraphId,
            subgraphs[_subgraphId].totalIndexingStake
        );
    }

    // TODO - implement partial logouts for these two functions
    /**
     * @dev Indexing node can start logout process
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     */
    function beginLogout(bytes32 _subgraphId) external {
        require(indexNodes[_subgraphId][msg.sender].amountStaked > 0);
        require(indexNodes[_subgraphId][msg.sender].logoutStarted == 0);
        indexNodes[_subgraphId][msg.sender].logoutStarted = block.timestamp;

        // Return the amount the Indexing Node has staked
        uint256 _stake = indexNodes[_subgraphId][msg.sender].amountStaked;
        indexNodes[_subgraphId][msg.sender].amountStaked = 0;
        // Return any outstanding fees accrued the Indexing Node does not have yet
        uint256 _fees = indexNodes[_subgraphId][msg.sender].feesAccrued;
        indexNodes[_subgraphId][msg.sender].feesAccrued = 0;
        // If we are dealing with the graph subgraph bootstrap index nodes
        if (_subgraphId == graphSubgraphID) {
            (bool found, uint256 userIndex) = findGraphIndexerIndex(msg.sender);
            assert(found == true);
            // Note, this does not decrease the length of the array
            // It just sets this index to 0x0000...
            // TODO - does the above statement introduce risk of this list getting too long? And creating a denial of service? I believe it will. To investigate in BETA
            delete graphIndexNodeAddresses[userIndex];
        }
        // Decrement the total amount staked by the amount being returned
        subgraphs[_subgraphId].totalIndexingStake -= _stake;

        // Increase thawingTokens to begin thawing
        indexNodes[_subgraphId][msg.sender].lockedTokens += (_stake + _fees);

        emit IndexNodeBeginLogout(msg.sender, _subgraphId, _stake, _fees);
    }

    /**
     * @dev Indexing node can finish the logout process after a thawing off period
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     */
    function finalizeLogout(bytes32 _subgraphId) external {
        // TODO - BUG, you can call finalize logout here, without ever calling beginLogout, and it will work
        require(
            indexNodes[_subgraphId][msg.sender].logoutStarted + thawingPeriod <=
                block.timestamp
        );

        uint256 _amount = indexNodes[_subgraphId][msg.sender].lockedTokens;
        // Reset the index node
        delete indexNodes[_subgraphId][msg.sender];

        // Remove an indexer from the subgraph
        subgraphs[_subgraphId].totalIndexers -= 1;

        assert(token.transfer(msg.sender, _amount));

        emit IndexNodeFinalizeLogout(msg.sender, _subgraphId);
    }

    /**
     * @dev Distribute the channel fees to the given Indexing Node and all the Curators
     *      for that subgraph. Curator fees are applied through reserve balance increase
     *      so every Curator logout will earn back more coins back per share, and shares
     *      cost more to buy.
     * @param _subgraphId <bytes32> - Subgraph that the fees were accrued for.
     * @param _indexingNode <address> - Indexing Node that earned the fees.
     * @param _feesEarned <uint256> - Total amount of fees earned.
     */
    // function distributeChannelFees(
    //     bytes32 _subgraphId,
    //     address _indexingNode,
    //     uint256 _feesEarned
    // ) private {
    //     // Each share minted gives basis point (0.01%) of the fee collected in that subgraph.
    //     uint256 _curatorRewardBasisPts = subgraphs[_subgraphId]
    //         .totalCurationShares *
    //         BASIS_PT;
    //     assert(_curatorRewardBasisPts < MAX_PPM); // should be less than 100%
    //     uint256 _curatorPortion = (_curatorRewardBasisPts * _feesEarned) /
    //         MAX_PPM;
    //     // Give the indexing node their part of the fees
    //     indexingNodes[_subgraphId][msg.sender].feesAccrued += (_feesEarned -
    //         _curatorPortion);
    //     // Increase the token balance for the subgraph (each share gets more tokens when sold)
    //     subgraphs[_subgraphId].totalCurationStake += _curatorPortion;
    // }

    /**
     * @dev The Indexing Node can get all of their accrued fees for a subgraph at once.
     *      Indexing Node would be able to log out all the fees they earned during a dispute.
     * @param _subgraphId <bytes32> - Subgraph the Indexing Node wishes to withdraw for.
     */
    function withdrawFees(bytes32 _subgraphId) external {
        uint256 _feesAccrued;
        _feesAccrued = indexNodes[_subgraphId][msg.sender].feesAccrued;
        require(_feesAccrued > 0);
        indexNodes[_subgraphId][msg.sender].feesAccrued = 0; // Re-entrancy protection
        token.transfer(msg.sender, _feesAccrued);
    }

    /**
     * @dev A function to help find the location of the indexer in the dynamic array. Note that
            it must return a bool if the value was found, because an index of 0 can be literally the
            index of 0, or else it refers to an address that was not found.
     * @param _indexer <address> - The address of the indexer to look up.
    */
    function findGraphIndexerIndex(address _indexer)
        private
        view
        returns (bool found, uint256 userIndex)
    {
        // We must find the indexers location in the array first
        for (uint256 i; i < graphIndexNodeAddresses.length; i++) {
            if (graphIndexNodeAddresses[i] == _indexer) {
                userIndex = i;
                found = true;
                break;
            }
        }
    }
}
