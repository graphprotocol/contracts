pragma solidity ^0.5.2;

import "./Governed.sol";


contract GNS is Governed {
    /*
    * @title Graph Name Service (GNS) contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    * @author Ashoka Finley
    * @notice Contract Specification:
    *
    * Subgraph IDs : Subgraph definitions are immutable, even though the actual
    * data ingested may grow -- each subgraph manifest is hashed in its IPLD
    * canonical serialized form, to produce a unique Id. Nodes in the peer-to-peer
    * network use this Id to communicate who is indexing and caching what data, as
    * well as route queries through the network. The self-certifying nature of
    * subgraph IDs also make them useful for providing attestations and filing disputes.
    *
    * Domains : Subgraph IDs can also be associated with a domain name in the Graph
    * Name Service (GNS) to provide a mutable reference to a subgraph. This can be
    * useful for writing more human readable queries, always querying the latest version
    * of a subgraph, specifying relationships between subgraphs or mutably referencing a
    * subgraph in smart contracts. A domain can be registered with registerDomain(),
    * and can be considered as a top level domain, where subdomains can be registered
    * under.
    *
    * Subdomains : An owner of a domain in the GNS may wish to deploy multiple subgraphs
    * to a single domain, and have them exist in separate namespaces. Sub-domains enable
    * this use case, and add an optional additional layer of namespacing beyond that
    * already provided by the top level domains. Subdomains and Domains are both stored
    * in the domains mapping under the hash of their strings.
    *
    * Account metadata and subgraph metadata : Data that doesn't need to be stored on
    * chain, such as descriptions of subgraphs or account images are stored on IPFS.
    * This data can be retrieved from the IPFS hashes that are emitted through the
    * metadata events.
    *
    */

    /* Events */
    event DomainAdded(
        bytes32 indexed topLevelDomainHash,
        address indexed owner,
        string domainName
    );
    event DomainTransferred(
        bytes32 indexed domainHash,
        address indexed newOwner
    );
    event SubgraphCreated(
        bytes32 indexed topLevelDomainHash,
        bytes32 indexed registeredHash,
        string subdomainName,
        address indexed owner
    );
    event SubgraphIDUpdated(
        bytes32 indexed domainHash,
        bytes32 indexed subgraphID
    );
    event DomainDeleted(bytes32 indexed domainHash);
    event AccountMetadataChanged(
        address indexed account,
        bytes32 indexed ipfsHash
    );
    event SubgraphMetadataChanged(
        bytes32 indexed domainHash,
        bytes32 indexed ipfsHash
    );

    /* TYPES */
    struct Domain {
        address owner;
        bytes32 subgraphID;
    }

    /* STATE VARIABLES */
    // Storage of a hashed top level domain to owners.
    mapping(bytes32 => Domain) public domains;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor */
    constructor(address _governor) public Governed(_governor) {}

    /* Graph Protocol Functions */

    modifier onlyDomainOwner(bytes32 _domainHash) {
        require(
            msg.sender == domains[_domainHash].owner,
            "Only domain owner can call."
        );
        _;
    }

    /*
     * @notice Register a domain to an owner.
     * @param _domainName <string> - Domain name, which is treated as a username.
     */
    function registerDomain(string calldata _domainName) external {
        bytes32 hashedName = keccak256(abi.encodePacked(_domainName));
        // Require that this domain is not yet owned by anyone.
        require(
            domains[hashedName].owner == address(0),
            "Domain is already owned."
        );
        domains[hashedName].owner = msg.sender;
        emit DomainAdded(hashedName, msg.sender, _domainName);
    }

    /*
     * @notice Create a subgraph by registering a subdomain, or registering the top level
     * domain as a subgraph.
     * @notice To register to the top level domain, pass _subdomainName as a blank string.
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the top level domain name.
     * @param _subdomainName <string> - Name of the Subdomain. If you were
     * registering 'david.thegraph', _subdomainName would be just 'david'.
     * @param _ipfsHash <bytes32> - Hash of the subgraph metadata, such as description.
    */
    function createSubgraph(
        bytes32 _topLevelDomainHash,
        string calldata _subdomainName,
        bytes32 _ipfsHash
    ) external onlyDomainOwner(_topLevelDomainHash) {
        bytes32 domainHash;
        bytes32 subdomainHash = keccak256(abi.encodePacked(_subdomainName));

        // Subdomain is blank, therefore we are setting the subgraphID of the top level domain
        if (subdomainHash == keccak256("")) {
            // The domain hash ends up being the top level domain hash.
            domainHash = _topLevelDomainHash;
        } else {
            // The domain hash becomes the subdomain concatenated with the top level domain hash.
            domainHash = keccak256(
                abi.encodePacked(subdomainHash, _topLevelDomainHash)
            );
            require(
                domains[domainHash].owner == address(0),
                "Someone already owns this subdomain."
            );
            domains[domainHash].owner = msg.sender;
        }

        // Note - subdomain name and IPFS hash are only emitted through the events.
        // Note - if the subdomain is blank, the domain hash ends up being the top level
        // domain hash, not the hash of a blank string.
        emit SubgraphCreated(
            _topLevelDomainHash,
            domainHash,
            _subdomainName,
            msg.sender
        );
        emit SubgraphMetadataChanged(domainHash, _ipfsHash);
    }

    /*
     * @notice Update an existing subdomain with a subgraph ID.
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the domain.
     */
    function updateDomainSubgraphID(bytes32 _domainHash, bytes32 _subgraphID)
        external
        onlyDomainOwner(_domainHash)
    {
        require(
            _subgraphID != bytes32(0),
            "If you want to reset the subgraphID, call deleteSubdomain."
        );
        domains[_domainHash].subgraphID = _subgraphID;
        emit SubgraphIDUpdated(_domainHash, _subgraphID);
    }

    /*
     * @notice Remove an existing domain owner and subgraphID
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     */
    function deleteSubdomain(bytes32 _domainHash)
        external
        onlyDomainOwner(_domainHash)
    {
        delete domains[_domainHash];
        emit DomainDeleted(_domainHash);
    }

    /*
     * @notice Transfer ownership of domain by existing domain owner.
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     * @param _newOwner <address> - New owner of the domain.
     */
    function transferDomainOwnership(bytes32 _domainHash, address _newOwner)
        external
        onlyDomainOwner(_domainHash)
    {
        require(
            _newOwner != address(0),
            "If you want to reset the owner, call deleteSubdomain."
        );
        domains[_domainHash].owner = _newOwner;
        emit DomainTransferred(_domainHash, _newOwner);
    }

    /*
     * @notice Change or initalize the Account Metadata, which is stored in a schema on IPFS.
     * @dev Only the msg.sender can do this.
     *
     * @param _ipfsHash <bytes32> - Hash of the IPFS file that stores the account metadata.
     * @param _account <address> - msg.sender.
     */
    function changeAccountMetadata(bytes32 _ipfsHash) external {
        emit AccountMetadataChanged(msg.sender, _ipfsHash);
    }

    /*
    * @notice Change or initalize the Account Metadata, which is stored in a schema on IPFS.
    * @dev Only the msg.sender can do this.
    *
    * @param _ipfsHash <bytes32> - Hash of the IPFS file that stores the subgraph metadata.
    * @param _domainHash <bytes32> - Hash of the domain name.
    */
    function changeSubgraphMetadata(bytes32 _domainHash, bytes32 _ipfsHash)
        public
        onlyDomainOwner(_domainHash)
    {
        emit SubgraphMetadataChanged(_domainHash, _ipfsHash);
    }
}
