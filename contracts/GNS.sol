pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";
import "./erc1056/IEthereumDIDRegistry.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized namings system for subgraphs
 * used in the scope of the Graph Network. It translates subgraph names into subgraph versions.
 * Each version is associated with a Subgraph Deployment. The contract no knowledge of human
 * readable names. All human readable names emitted in events.
 */
contract GNS is Governed {
    // -- State --

    // graphAccountID => subgraphNumber => subgraphDeploymentID
    // graphAccountID = An ERC-1056 ID
    // subgraphNumber = Simply a number associated to a graph accounts deployed subgraph. This
    //                  is used to create a subgraphID (graphAccountID + subgraphNumber)
    // subgraphDeploymentID = The IPFS hash of the manifest of the subgraph
    mapping(address => mapping(uint256 => bytes32)) public subgraphs;

    // graphAccount => a counter of the accounts subgraph deployments
    mapping(address => uint256) public graphAccountSubgraphNumbers;

    // ERC-1056 contract reference
    IEthereumDIDRegistry public erc1056Registry;

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
        bytes32 nameIdentifier,
        string name,
        bytes32 metadataHash
    );

    /**
     * @dev Emitted when a graph account deprecated one of their subgraphs
     */
    event SubgraphDeprecated(address graphAccount, uint256 subgraphNumber);

    /**
    @dev Modifier that allows a function to be called by owner of a graph account. Only owner can call
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
     * @param _didRegistry Address of the Ethereum DID registry
     */
    constructor(address _governor, address _didRegistry) public Governed(_governor) {
        erc1056Registry = IEthereumDIDRegistry(_didRegistry);
    }

    /**
     * @dev Allows a graph account to publish a new subgraph, which means a new subgraph number
     * will be allocated. It then will call publish version. Subsequent versions can be created
     * by calling publishVersion() directly.
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _nameIdentifier The value used to look up ownership in the naming system
     * @param _name Name of the subgraph, from any valid system
     * @param _metadataHash IPFS hash for the subgraph, and subgraph version metadata
     */
    function publishNewSubgraph(
        address _graphAccount,
        bytes32 _subgraphDeploymentID,
        bytes32 _nameIdentifier,
        string calldata _name,
        bytes32 _metadataHash
    ) external onlyGraphAccountOwner(_graphAccount) {
        uint256 subgraphNumber = graphAccountSubgraphNumbers[_graphAccount];
        publishVersion(
            _graphAccount,
            subgraphNumber,
            _subgraphDeploymentID,
            _nameIdentifier,
            _name,
            _metadataHash
        );
        graphAccountSubgraphNumbers[_graphAccount]++;
    }

    /**
     * @dev Allows a graph account to publish a subgraph, with a version, a name, and metadata
     * Graph account must be owner on their ERC-1056 identity
     * Graph account must own the name of the name system they are linking to the subgraph
     * Version is derived from the occurance of SubgraphPublish being emitted. i.e. version 0
     * is the first time the event is emitted for the graph account and subgraph number
     * combination.
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _nameIdentifier The value used to look up ownership in the naming system
     * @param _name Name of the subgraph, from any valid system
     * @param _metadataHash IPFS hash for the subgraph, and subgraph version metadata
     */
    function publishNewVersion(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphDeploymentID,
        bytes32 _nameIdentifier,
        string calldata _name,
        bytes32 _metadataHash
    ) external onlyGraphAccountOwner(_graphAccount) {
        require(
            subgraphs[_graphAccount][_subgraphNumber] != 0 || // Hasn't been created yet
                _subgraphNumber < graphAccountSubgraphNumbers[_graphAccount], // Was created, but deprecated
            "GNS: Cant publish a version directly for a subgraph that wasnt created yet"
        );

        publishVersion(
            _graphAccount,
            _subgraphNumber,
            _subgraphDeploymentID,
            _nameIdentifier,
            _name,
            _metadataHash
        );
    }

    /**
     * @dev Internal function used by both external publishing functions
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _nameIdentifier The value used to look up ownership in the naming system
     * @param _name Name of the subgraph, from any valid system
     * @param _metadataHash IPFS hash for the subgraph, and subgraph version metadata
     */
    function publishVersion(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphDeploymentID,
        bytes32 _nameIdentifier,
        string memory _name,
        bytes32 _metadataHash
    ) internal {
        require(_subgraphDeploymentID != 0, "GNS: Cannot set to 0 in publish");

        // Stores a subgraph deployment ID, which indicates a version has been created
        subgraphs[_graphAccount][_subgraphNumber] = _subgraphDeploymentID;
        // Emit version and name data
        emit SubgraphPublished(
            _graphAccount,
            _subgraphNumber,
            _subgraphDeploymentID,
            _nameIdentifier,
            _name,
            _metadataHash
        );
    }

    /**
     * @dev Deprecate a subgraph. Can only be done by the erc-1506 identity owner.
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     */
    function deprecate(address _graphAccount, uint256 _subgraphNumber)
        external
        onlyGraphAccountOwner(_graphAccount)
    {
        require(
            subgraphs[_graphAccount][_subgraphNumber] != 0,
            "GNS: Cannot deprecate a subgraph which does not exist"
        );
        delete subgraphs[_graphAccount][_subgraphNumber];
        emit SubgraphDeprecated(_graphAccount, _subgraphNumber);
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
