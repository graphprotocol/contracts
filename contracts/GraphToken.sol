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
    
    /* STATE VARIABLES */
    // Token details
    string public symbol = "GRT";
    string public  name = "Graph Token";
    uint8 public decimals = 18;

    // Treasurers map to true
    address[] private treasurers;

    /* Modifiers */
    // Only a treasurers address is allowed
    modifier onlyTreasurer () {
        bool isTreasurer = false;
        for (uint i = 0; i < treasurers.length; i++) {
            if (msg.sender == treasurers[i]) isTreasurer = true;
        }
        require(isTreasurer);
        _;
    }
    
    /* Init Graph Token contract */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    /* @param _initialSupply <uint256> - Initial supply of Graph Tokens */
    constructor (address _governor, uint256 _initialSupply) public Governed (_governor) {
        totalSupply = _initialSupply * 10**uint(decimals); // Initial totalSupply
        treasurers.push(_governor); // Governor (multisig) is initially the sole treasurer

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
    /**
     * @dev Internal function that mints an amount of the token and assigns it to
     * an account. This encapsulates the modification of balances such that the
     * proper events are emitted.
     * @param account <address> - The account that will receive the created tokens.
     * @param value <uint256> - The amount that will be created.
     */
    function mint (address _account, uint256 _value) external onlyTreasurer {
        require(_account != address(0));

        totalSupply += _value;
        balances[_account] += _value;
        emit Transfer(address(0), _account, _value);
    }

    /**
     * @dev Burns a specific amount of tokens from the target address and decrements allowance
     * @param _account <address> - The to burn tokens for.
     * @param _value <uint256> - The amount that will be burnt.
     */
    function burnFrom (address _account, uint256 _value) public {

        // check balance
        require(_value <= balances[_account]);

        // check allowances before burning someone else's tokens
        if (msg.sender != _account) {
            require(_value <= allowed[_account][msg.sender]); // check allowance
            allowed[_account][msg.sender] -= _value;
        }

        // Adjust balances and emit
        balances[_account] -= _value;
        totalSupply -= _value;
        emit Transfer(_account, address(0), _value);
    }

    /* 
     * @notice Add a Treasurer to the treasurers list
     * @dev Only DAO owner may do this
     *
     * @param _newTreasurer <address> - Address of the Treasurer to be added
     */
    function addTreasurer (address _newTreasurer) public onlyGovernance {
        // Prevent saving a duplicate
        bool duplicate;
        for (uint i = 0; i < treasurers.length; i++) {
            if (treasurers[i] == _newTreasurer) duplicate = true;
        }
        require(!duplicate);

        // Add address to treasurers list
        treasurers.push(_newTreasurer);
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
        
        // Remove _removedTreasurer from treasurers list
        uint i = 0;
        while (treasurers[i] != _removedTreasurer) {
            i++;
        }
        treasurers[i] = treasurers[treasurers.length - 1];
        treasurers.length--;
    }

    // ------------------------------------------------------------------------
    // Don't accept ETH
    // ------------------------------------------------------------------------
    function () external payable {
        revert();
    }

}