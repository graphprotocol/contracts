pragma solidity ^0.5.2;

import "./Ownable.sol";

contract GNS is Owned {
    
    /* 
    * @title Graph Name Service (GNS) contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * Subgraph IDs : Subgraph definitions are immutable, even though the actual 
    * data ingested may grow -- each subgraph manifest is hashed in its IPLD 
    * canonical serialized form, to produce a unique ID. Nodes in the peer-to-peer 
    * network use this ID to communicate who is indexing and caching what data, as 
    * well as route queries through the network. The self-certifying nature of 
    * subgraph IDs also make them useful for providing attestations and filing disputes.
    * 
    * Domains : Subgraph IDs can also be associated with a domain name in the Graph 
    * Name Service (GNS) to provide a mutable reference to a subgraph. This can be 
    * useful for writing more human readable queries, always querying the latest version
    * of a subgraph, specifying relationships between subgraphs or mutably referencing a 
    * subgraph in smart contracts.
    *
    * Deploying a subgraph to a domain also enables discoverability, as explorer UIs will
    * be built on top of the GNS.
    *
    * Subdomains : An owner of a domain in the GNS may wish to deploy multiple subgraphs 
    * to a single domain, and have them exist in separate namespaces. Sub-domains enable 
    * this use case, and add an optional additional layer of namespacing beyond that 
    * already provided by the top level domains.
    *
    * See: https://github.com/graphprotocol/specs/tree/master/data-model for details.
    *
    * Requirements ("GNS" contract):
    * @req 01 Maps owners to domains
    * @req 02 Maps domain names to subgraphIds
    * @req 03 Maps subdomain names to domains of subgraphIds
    * @req 04 Top-level registrar assigns names to Ethereum Addresses (not subgraphIds?)
    *   Q. 04 is a separate use for GNS? A simple map to ETH addresses? Or is a subgraphId an address?
    * ...
    */

    /* STATE VARIABLES */
    // Storage of Domain Names mapped to subgraphId's
    mapping (string => string) internal gnsDomains;

    // Storage of Sub Domain Names mapped to subgraphId's
    // @todo: NOT FEASIBLE - REVISE
    // @dev Define requirements further
    mapping (string => mapping (string => string)) internal gnsSubDomains;

    /* Contract Constructor */
    constructor () public {}

    /* Graph Protocol Functions */
    /**
     * @dev Retrieve subgraphId for given Domain Name
     * @param _domain <string> - Domain of targeted subgraphId
     */
    function getDomainSubgraphId (string memory _domain) public view returns (string memory);

    /**
     * @dev Retrieve subgraphId for given Subdomain Name
     * @param _subDomain <string> - Domain of targeted subgraphId
     */
    function getSubDomainSubgraphId (string memory _subDomain) public view returns (string memory);

    // WIP...
     
}