pragma solidity ^0.5.2;

import "./Governed.sol";

contract GNS is Governed {

    /* Events */
    event DomainAdded(bytes32 indexed topLevelDomainHash, address indexed owner, string domainName);
    event DomainTransferred(bytes32 indexed domainHash, address indexed newOwner);
    event SubgraphCreated(bytes32 indexed topLevelDomainHash, bytes32 indexed registeredHash, string subdomainName);
    event SubgraphDeployed(bytes32 indexed domainHash, bytes32 indexed subgraphID);
    event SubgraphIDChanged(bytes32 indexed domainHash, bytes32 indexed subgraphID);
    event DomainDeleted(bytes32 indexed domainHash);
    event AccountMetadataChanged(address indexed account, bytes32 indexed ipfsHash);
    event SubgraphMetadataChanged(bytes32 indexed domainHash, bytes32 indexed ipfsHash);

    /* TYPES */
    struct Domain {
        address owner;
        bytes32 subgraphID;
    }

    /* STATE VARIABLES */
    // Storage of a hashed top level domain to owners.
    mapping(bytes32 => Domain) public domains;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed(_governor) {}

    /* Graph Protocol Functions */

    modifier onlyDomainOwner (bytes32 _domainHash) {
        require(msg.sender == domains[_domainHash].owner, "Only domain owner can call.");
        _;
    }

    /*
     * @notice Register a domain to an owner.
     * @param _domainName <string> - Domain name, which is treated as a username.
     */
    function registerDomain(string calldata _domainName) external {
        // Require that this domain is not yet owned by anyone.
        require(domains[keccak256(abi.encodePacked(_domainName))].owner == address(0), 'Domain is already owned.');
        domains[keccak256(abi.encodePacked(_domainName))].owner = msg.sender;
        emit DomainAdded(keccak256(abi.encodePacked(_domainName)), msg.sender, _domainName);
    }

    /*
     * @notice Create a subgraph by registering a subdomain, or registering the top level domain as a subgraph.
     * @notice To only register to the top level domain, pass _subdomainName as a blank string.
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the top level domain name.
     * @param _subdomainName <string> - Name of the Subdomain. If you were registering 'david.thegraph', _subdomainName would be just 'david'.
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
            // The domain hash becomes the hash the subdomain concatenated with the top level domain hash.
            domainHash = keccak256(abi.encodePacked(subdomainHash, _topLevelDomainHash));
            require(domains[domainHash].owner == address(0), 'Someone already owns this subdomain.');
            domains[domainHash].owner = msg.sender;
        }

        // Note - subdomain name and ipfs hash are only emitted through the events.
        // Note - if the subdomain is blank, the domain hash ends up being the top level domain hash, not the hash of a blank string.
        emit SubgraphCreated(_topLevelDomainHash, domainHash, _subdomainName);
        emit SubgraphMetadataChanged(domainHash, _ipfsHash);
    }

    /*
     * @notice Deploy a subgraph by registering a subgraph ID to a domain. Only works when the subgraph has not been registered yet. After this, updates can be made via changeDomainSubgraphID
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the subdomain.
     */
    function deploySubgraph(
        bytes32 _domainHash,
        bytes32 _subgraphID
    ) external onlyDomainOwner(_domainHash) {
        require(domains[_domainHash].subgraphID == bytes32(0), 'The subgraph ID for this domain has already been set. You must call changeDomainSubgraphID it you wish to change it.');
        domains[_domainHash].subgraphID = _subgraphID;
        emit SubgraphDeployed(_domainHash, _subgraphID);
    }

    /*
     * @notice Update an existing subdomain with a different subgraph ID.
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the domain.
     */
    function changeDomainSubgraphID(
        bytes32 _domainHash,
        bytes32 _subgraphID
    ) external onlyDomainOwner(_domainHash) {
        require(domains[_domainHash].subgraphID != bytes32(0), 'The subgraph ID must have been set at least once in order to change it.');
        require(_subgraphID != bytes32(0), 'If you want to reset the subgraphID, call deleteSubdomain.');
        domains[_domainHash].subgraphID = _subgraphID;
        emit SubgraphIDChanged(_domainHash, _subgraphID);
    }

    /*
     * @notice Remove an existing domain owner and subgraphID
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     */
    function deleteSubdomain(bytes32 _domainHash) external onlyDomainOwner(_domainHash) {
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
    function transferDomainOwnership(bytes32 _domainHash, address _newOwner) external onlyDomainOwner(_domainHash) {
        require(_newOwner != address(0), 'If you want to reset the owner, call deleteSubdomain.');
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
    function changeSubgraphMetadata(bytes32 _ipfsHash, bytes32 _domainHash) public onlyDomainOwner(_domainHash) {
        emit SubgraphMetadataChanged(_domainHash, _ipfsHash);
    }

}
