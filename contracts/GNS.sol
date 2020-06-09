pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";
import "./erc1056/EthereumDIDRegistry.sol";
import "./ens/ENS.sol";
import "./ens/TextResolver.sol";
import "./ens/StringUtils.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized namings system for subgraphs
 * used in the scope of the Graph Network. It translates subgraph names into subgraph versions.
 * Each version is associated with a Subgraph Deployment. The contract no knowledge of human
 * readable names. All human readable names emitted in events.
 */
contract GNS is Governed {
    using StringUtils for string;

    // -- Types --

    enum NameSystem { GNS }

    // -- State --

    // graphAccountID => subgraphNumber => subgraphDeploymentID
    // graphAccountID = An ERC-1056 ID
    // subgraphNumber = Simply a number associated to a graph accounts deployed subgraph. This
    //                  is used to create a subgraphID (graphAccountID + subgraphNumber)
    // subgraphDeploymentID = The IPFS hash of the manifest of the subgraph
    mapping(address => mapping(uint256 => bytes32)) public subgraphs;

    // ERC-1056 contract reference
    EthereumDIDRegistry public erc1056Registry;
    // ENS contract reference. Importing owner()
    ENS public ens;
    // ENS pubic resolver contract reference. Importing text() from TextResolver
    TextResolver public publicResolver;

    // -- Events --

    /**
     * @dev Emitted when a `graph account` publishes a `subgraph` with a `version`.
     * Every time this event is emitted, indicates a new version has been created.
     * The event also emits a `metadataHash` with subgraph details and version details.
     * Name data is emitted, as well as the name system.
     */
    event SubgraphPublished(
        address graphAccount,
        uint256 subgraphNumber,
        bytes32 subgraphDeploymentID,
        string name,
        NameSystem system,
        bytes32 metadataHash
    );

    /**
     * @dev Emitted when a graph account unpublished one of their subgraphs
     */
    event SubgraphUnpublished(address graphAccount, uint256 subgraphNumber);

    /**
     * @dev Emitted when a graph account sets their default name associated with their account
     */
    event SetDefaultName(
        address graphAccount,
        string name,
        NameSystem system,
        bytes32 systemIdentifier
    );

    /**
    @dev Modifer that allows a function to be called by owner of a graph account. Only owner can call
    @param _graphAccount Address of the graph account
    */
    modifier onlyGraphAccountOwner(address _graphAccount) {
        address graphAccountOwner = erc1056Registry.identityOwner(_graphAccount);
        require(graphAccountOwner == msg.sender, "GNS: Only graph account owner can call");
        _;
    }

    /**
     * @dev Contract Constructor.
     * @param _governor Owner address of this contract
     * @param _ens Address of the ENS Contract
     * @param _publicResolver Address of the ENS Public Resolver
     */
    constructor(
        address _governor,
        address _ens,
        address _publicResolver
    ) public Governed(_governor) {
        ens = ENS(_ens);
        publicResolver = TextResolver(_publicResolver);
    }

    /**
     * @dev Allows a graph account to publish a subgraph, with a version, a name, and metadata
     * Graph account must be owner on their ERC-1056 identity
     * Graph account must own the name of the name system they are linking to the subgraph
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     * @param _nameSystemIdentifier The value used to look up ownership in the naming system
     * @param _name Name of the subgraph, from any valid system
     * @param _system Name system being used to claim
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _metadataHash IPFS hash for the subgraph, and subgraph version metadata
     */
    function publish(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _nameSystemIdentifier,
        string calldata _name,
        NameSystem _system,
        bytes32 _subgraphDeploymentID,
        bytes32 _metadataHash
    ) external onlyGraphAccountOwner(_graphAccount) {
        require(_subgraphDeploymentID != 0, "GNS: Cannot set to 0 in publish");
        verifyENS(_nameSystemIdentifier, _graphAccount);

        // Stores a subgraph deployment ID, which indicates a version has been created
        subgraphs[_graphAccount][_subgraphNumber] = _subgraphDeploymentID;
        // Emit version and name data
        emit SubgraphPublished(
            _graphAccount,
            _subgraphNumber,
            _subgraphDeploymentID,
            _name,
            _system,
            _metadataHash
        );
    }

    /**
     * @dev Unpublish a subgraph. Can only be done by the erc-1506 identity owner.
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     */
    function unpublish(address _graphAccount, uint256 _subgraphNumber)
        external
        onlyGraphAccountOwner(_graphAccount)
    {
        delete subgraphs[_graphAccount][_subgraphNumber];
        emit SubgraphUnpublished(_graphAccount, _subgraphNumber);
    }

    /**
     * @dev Set default name for a graph account through an event. Can only be done by
     * the erc-1506 identity owner.
     * @param _graphAccount Graph account with name being updated
     * @param _nameSystemIdentifier The value used to look up ownership in the naming system
     * @param _name Name of the subgraph
     * @param _system Name system being used to claim
     */
    function updateGraphAccountDefaultName(
        address _graphAccount,
        bytes32 _nameSystemIdentifier,
        NameSystem _system,
        string calldata _name
    ) external {
        verifyENS(_nameSystemIdentifier, _graphAccount);
        emit SetDefaultName(_graphAccount, _name, _system, _nameSystemIdentifier);
    }

    /**
     * @dev Verify the Graph Account owns the ENS node, and they set their text record on the
     * ENS Public Resolver. Text record key is "GRAPH NAME SERVICE". Record should return the
     * Graph Account ID.
     * @param _node ENS node being verified
     * @param _graphAccount Account getting verified
     */
    function verifyENS(bytes32 _node, address _graphAccount) private view {
        address owner = ens.owner(_node);
        require(
            owner == _graphAccount,
            "GNS: The Graph Account must own the ENS name they are registering"
        );
        string memory textRecord = publicResolver.text(_node, "GRAPH NAME SERVICE");
        address textRecordConverted = textRecord.parseAddr();
        require(
            textRecordConverted == _graphAccount,
            "GNS: The graph account must register a text record on ENS"
        );
    }

    /**
     * @dev Return whether a subgraph name is published.
     * @param _graphAccount Account being checked
     * @param _subgraphNumber Subgraph number being checked for publishing
     * @return Return true if subgraph is currently published
     */
    function isPublished(address _graphAccount, uint256 _subgraphNumber)
        public
        view
        returns (bool)
    {
        return subgraphs[_graphAccount][_subgraphNumber] != 0;
    }
}
