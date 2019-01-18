pragma solidity ^0.5.2;

import "./Governed.sol";
import "./MintableERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "./StandardERC20Token.sol"; // redundant? openzeppelin ERC20 is inherited in ERC20Burnable
/**
 * @NOTICE: OpenZeppelin ERC20 state variables use a preceding underscore
 *      Ex: _balances vs balances, _totalSupply vs totalSupply, etc.
 */

// ----------------------------------------------------------------------------
// Burnable ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract GraphToken is
    Governed,
    StandardERC20Token, // redundant?
    MintableERC20Interface,
    ERC20Burnable // openzeppelin contract inherits ERC20
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
    
    /* STATE VARIABLES */
    // Treasurers map to true
    address[] private treasurers;

    /* Modifiers */
    // Only a treasurers address is allowed
    modifier onlyTreasurer ();
    
    /* Init Graph Token contract */
    /* @PARAM _initialSupply <uint256> - Initial supply of Graph Tokens */
    constructor (uint256 _initialSupply) public;
    
    /* Graph Protocol Functions */
    /**
     * @dev Internal function that mints an amount of the token and assigns it to
     * an account. This encapsulates the modification of balances such that the
     * proper events are emitted.
     * @param account <address> - The account that will receive the created tokens.
     * @param value <uint256> - The amount that will be created.
     */
    function mint(address _account, uint256 _value) external onlyTreasurer;

    /**
     * @dev Internal function that burns an amount of the token of a given
     * account.
     * @param _account <address> - The to burn tokens for.
     * @param _value <uint256> - The amount that will be burnt.
     */
    function burnFrom(address _account, uint256 _value) public;

    /* 
     * @notice Add a Treasurer to the treasurers list
     * @dev Only DAO owner may do this
     *
     * @param _newTreasurer <address> - Address of the Treasurer to be added
     */
    function addTreasurer (address _newTreasurer) public onlyGovernance;

    /* 
     * @notice Remove a Treasurer from the treasurers mapping
     * @dev Only DAO owner may do this
     *
     * @param _removedTreasurer <address> - Address of the Treasurer to be removed
     */
    function removeTreasurer (address _removedTreasurer) public onlyGovernance;

}