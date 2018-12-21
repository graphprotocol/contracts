pragma solidity ^0.5.1;

// ----------------------------------------------------------------------------
// ERC Token Standard #20 Abstract Contract / Interface
// ----------------------------------------------------------------------------
contract StandardERC20Token {

    /* STATE VARIABLES */
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    // Total amount of tokens
    uint256 public totalSupply;
    
    // Balances for each account
    mapping (address => uint256) balances;
    
    // Owner of account approves the transfer of an amount to another account
    mapping (address => mapping (address => uint256)) allowed;
    
    // Token details
    string public symbol;
    string public  name;
    uint8 public decimals;

    /* ERC20 BASIC */
    // Get the account balance of another account with address _owner
    function balanceOf(address _tokenOwner) public view returns (uint balance);
    
    // Returns the amount which _spender is still allowed to withdraw from _owner
    function allowance(address _tokenOwner, address _spender) public view returns (uint remaining);

    // Send _value amount of tokens to address _to
    function transfer(address _to, uint _value) public returns (bool success);

    /* ERC20 Standard */
    // Allow _spender to withdraw from your account, multiple times, up to the _value amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve(address _spender, uint _value) public returns (bool success);

    // Send _value amount of tokens from address _from to address _to
    function transferFrom(address _from, address _to, uint _value) public returns (bool success);

    // Triggered when tokens are transferred.
    event Transfer(address indexed _from, address indexed _to, uint _value);

    // Triggered whenever approve(address _spender, uint256 _value) is called.
    event Approval(address indexed _tokenOwner, address indexed _spender, uint _value);
 }

