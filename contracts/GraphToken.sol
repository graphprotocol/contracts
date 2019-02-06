pragma solidity ^0.5.2;

import "./Governed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";

// ----------------------------------------------------------------------------
// Burnable ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract GraphToken is
    Governed,
    ERC20Burnable,
    ERC20Mintable
{
    
    /* 
    * @title GraphToken contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * Graph Tokens will have variable inflation to rewards specific activities
    * in the network.
    * 
    * V1 Requirements ("GraphToken" contract):
    * @req 01 Implements ERC-20 Standards plus is Burnable (slashing) & Minting
    *   Minting: see https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/token/ERC20/ERC20Mintable.sol
    *       (Ignore roles, Treasures are allowed to mint)
    * @req 02 Has a treasurers list of contracts with permission to mint the token (i.e. Payment Channel Hub and Rewards Manager).
    * @req 03 Has owner which can set treasurers, upgrade contract and set any parameters controlled via governance.
    * @req 04 Allowances be used to delegate token burning 
    * @req 05 Constructor takes a param to set the initial supply of tokens
    * ...
    * V2 Requirements
    * @req 01 Majority of multiple treasurers can mint tokens.
    *
    * @question: To which address should the tokens be allocated? How will they be used? (crowd sale? init payment channel?)
    */

    /* Events */
    event AddTreasurer (address treasurer);
    event RemoveTreasurer (address treasurer);
    
    /* STATE VARIABLES */
    // Token details
    string public symbol = "GRT";
    string public  name = "Graph Token";
    uint8 public decimals = 18;

    // Treasurers map to true
    mapping (address => bool) public treasurers;

    /* Modifiers */
    // Only a treasurers address is allowed
    modifier onlyTreasurer () {
        require(treasurers[msg.sender]);
        _;
    }
    
    /* Init Graph Token contract */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    /* @param _initialSupply <uint256> - Initial supply of Graph Tokens */
    constructor (address _governor, uint256 _initialSupply) public Governed (_governor) {
        totalSupply = _initialSupply * 10**uint(decimals); // Initial totalSupply

        // Governor (multisig) is initially the sole treasurer
        treasurers[_governor] = true;
        emit AddTreasurer(_governor);

        // @question: Who should own the initial supply of tokens?
        // @dev If `governor` owns the tokens, we need to transfer when governor changes
        balances[msg.sender] = totalSupply; // Deployment address holds all tokens
        emit Transfer(
            address(0), // from
            msg.sender, // to
            totalSupply // value
        );
    }
    
    /* Graph Protocol Functions */
    /* 
     * @notice Add a Treasurer to the treasurers list
     * @dev Only DAO owner may do this
     *
     * @param _newTreasurer <address> - Address of the Treasurer to be added
     */
    function addTreasurer (address _newTreasurer) public onlyGovernance {
        treasurers[_newTreasurer] = true;
        emit AddTreasurer(_newTreasurer);
    }

    /* 
     * @notice Remove a Treasurer from the treasurers mapping
     * @dev Only DAO owner may do this
     *
     * @param _removedTreasurer <address> - Address of the Treasurer to be removed
     */
    function removeTreasurer (address _removedTreasurer) public onlyGovernance {
        // Sender cannot remove self
        require(msg.sender != _removedTreasurer);
        
        // Mark _removedTreasurer as false in mapping
        treasurers[_removedTreasurer] = false;
        emit RemoveTreasurer(_removedTreasurer);
    }

    // ------------------------------------------------------------------------
    // Don't accept ETH
    // ------------------------------------------------------------------------
    function () external payable {
        revert();
    }

}
