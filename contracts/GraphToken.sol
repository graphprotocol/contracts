pragma solidity ^0.5.1;

import "./Ownable.sol";
import "./BurnableERC20Token.sol";
import "./StandardERC20Token.sol";

// ----------------------------------------------------------------------------
// Burnable ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract GraphToken is
    Owned,
    StandardERC20Token,
    BurnableERC20Token
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
    * Requirements ("GraphToken" contract):
    * @req 01 Implements ERC-20 Standards plus is Burnable (slashing) & Minting
    *   Minting: see https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/token/ERC20/ERC20Mintable.sol
    *       (Ignore roles, Treasures are allowed to mint)
    * @req 02 Has approved treasurers with permission to mint the token (i.e. Payment Channel Hub and Rewards Manager).
    * @req 03 Has owner which can set treasurers, upgrade contract and set any parameters controlled via governance.
    * ...
    */
    
    /* STATE VARIABLES */
    // ------------------------------------------------------
    // Treasurers map to true
    mapping (address => bool) internal treasurers;
    // OR...
    // Single Treasurer (V1?)
    // address internal treasurer;
    // ------------------------------------------------------
 
    // Burn _value amount of your own tokens
    function burn(uint256 _value) public {
        // @TODO: check balance and burn tokens
    }

    
    /* Init Graph Token contract */
    constructor (uint256 _initialSupply) public {
        name = "The Graph Token"; // TODO: Confirm a name or lose this
        symbol = "TGT"; // TODO: Confirm a sybol or lose this
        decimals = 18;  // 18 is the most common number of decimal places
        totalSupply = _initialSupply * 10**uint(decimals);
        balances[owner] = totalSupply;
        emit Transfer(address(0), owner, totalSupply);
    }
    
    /* Graph Protocol Functions */
    /* 
     * @notice Add a Treasurer to the treasurers mapping
     * @dev Only DAO owner may do this
     *
     * @param _newTreasurer (address) Address of the Treasurer to be added
     */
    function addTreasurer (address _newTreasurer) public onlyOwner {
        treasurers[_newTreasurer] = true;
    }

    /* 
     * @notice Remove a Treasurer from the treasurers mapping
     * @dev Only DAO owner may do this
     *
     * @param _removedTreasurer (address) Address of the Treasurer to be removed
     */
    function removeTreasurer (address _removedTreasurer) public onlyOwner {
        treasurers[_removedTreasurer] = false;
    }

}