pragma solidity ^0.5.1;

import "./Ownable.sol";

// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/issues/20
// Constructed according to OpenZeppelin Burnable Token contract
// https://github.com/OpenZeppelin/zeppelin-solidity/
interface BurnableERC20 {

    /* ERC20 BASIC */
    // Get the total token supply
    function totalSupply() external view returns (uint256 _totalSupply);
 
    // Get the account balance of another account with address _owner
    function balanceOf(address _owner) external view returns (uint256 balance);
 
    // Send _value amount of tokens to address _to
    function transfer(address _to, uint256 _value) external returns (bool success);
 
    // Triggered when tokens are transferred.
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
 
    /* ERC20 Standard */
    // Allow _spender to withdraw from your account, multiple times, up to the _value amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve(address _spender, uint256 _value) external returns (bool success);
 
    // Triggered whenever approve(address _spender, uint256 _value) is called.
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
 
    // Returns the amount which _spender is still allowed to withdraw from _owner
    function allowance(address _owner, address _spender) external view returns (uint256 remaining);
 
    // Send _value amount of tokens from address _from to address _to
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    
    /* BURNABLE ERC20 */
    // Burn _value amount of your own tokens
    function burn(uint256 _value) external;

    // Triggered whenever burn(uint256 _value) is called
    event Burn(address indexed burner, uint256 value);
}


contract GraphToken is Ownable, BurnableERC20 {
    
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
    * @req 01 Implements ERC-20 (and what else?)
    * @req 02 Has approved treasurers with permission to mint the token (i.e. Payment Channel Hub and Rewards Manager).
    * @req 03 Has owner which can set treasurers, upgrade contract and set any parameters controlled via governance.
    * ...
    */
    
    /* STATE VARIABLES */
    uint public _totalSupply;
    
   // Treasurers map to true
    mapping (address => bool) internal treasurers;
    
    /* Init GraphToken contract */
    constructor (uint _initialSupply) public {
        _totalSupply = _initialSupply;
    }

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