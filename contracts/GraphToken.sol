pragma solidity ^0.5.2;

import "./Ownable.sol";
import "./MintableERC20.sol";
import "./BurnableERC20.sol";
import "./StandardERC20Token.sol";

// ----------------------------------------------------------------------------
// Burnable ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract GraphToken is
    Owned,
    StandardERC20Token,
    MintableERC20Interface,
    BurnableERC20Interface
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
    * @req 02 Has a single treasurer with permission to mint the token (i.e. Payment Channel Hub and Rewards Manager).
    * @req 03 Has owner which can set treasurers, upgrade contract and set any parameters controlled via governance.
    * ...
    * V2 Requirements
    * @req 01 Majority of multiple treasurers can mint tokens.
    *
    * @question: Will allowances be possible to delegate token burning to the contract (need?)
    * @question: Do we want to init the contract with a specific supply? To which address should the tokens be allocated? How will they be used? (crowd sale? init payment channel?)
    */
    
    /* STATE VARIABLES */
    // Treasurers map to true
    address[] private treasurers;

    /* Modifiers */
    modifier onlyTreasurer () {
        bool isTreasurer = false;
        for (uint i = 0; i < treasurers.length; i++) {
            if (msg.sender == treasurers[i]) isTreasurer = true;
        }
        require(isTreasurer);
        _;
    }
    
    /* Init Graph Token contract */
    /* @PARAM _initialSupply <uint256> - Initial supply of Graph Tokens */
    constructor (uint256 _initialSupply) public {
        
        name = "The Graph Token"; // TODO: Confirm a name or lose this
        symbol = "TGT"; // TODO: Confirm a sybol or lose this
        decimals = 18;  // 18 is the most common number of decimal places
        totalSupply = _initialSupply * 10**uint(decimals); // Initial totalSupply
        balances[msg.sender] = totalSupply; // Owner holds all tokens
        treasurers.push(msg.sender); // DAO owner is initially the sole treasurer
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    /* Graph Protocol Functions */
    /**
     * @dev Internal function that mints an amount of the token and assigns it to
     * an account. This encapsulates the modification of balances such that the
     * proper events are emitted.
     * @param account <address> - The account that will receive the created tokens.
     * @param value <uint256> - The amount that will be created.
     */
    function mint(address account, uint256 value) external onlyTreasurer {
        require(account != address(0));

        totalSupply += value;
        balances[account] += value;
        emit Transfer(address(0), account, value);
    }

    /**
     * @dev Internal function that burns an amount of the token of a given
     * account.
     * @param _account <address> - The to burn tokens for.
     * @param _value <uint256> - The amount that will be burnt.
     */
    function burn(address _account, uint256 _value) public {

        // check balance
        require(_value <= balances[_account]);

        // burn our own tokens or someone else's
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
    function addTreasurer (address _newTreasurer) public onlyOwner {
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
    function removeTreasurer (address _removedTreasurer) public onlyOwner {
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

}