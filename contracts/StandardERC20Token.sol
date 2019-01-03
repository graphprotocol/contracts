pragma solidity ^0.5.2;

import "./ApproveAndCallFallBack.sol";

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
    uint256 internal totalSupply;
    
    // Balances for each account
    mapping (address => uint256) internal balances;
    
    // Owner of account approves the transfer of an amount to another account
    mapping (address => mapping (address => uint256)) internal allowed;
    
    // Token details
    string public symbol;
    string public  name;
    uint8 public decimals;

    /* ERC20 BASIC */
    // ------------------------------------------------------------------------
    // Get the account balance of another account with address `_tokenOwner`
    // ------------------------------------------------------------------------
    function balanceOf(address _tokenOwner) public view returns (uint256 balance);

    // ------------------------------------------------------------------------
    // Returns the amount which _spender is still allowed to withdraw from _owner
    // ------------------------------------------------------------------------
    function allowance(address _tokenOwner, address _spender) public view returns (uint256 remaining);

    // ------------------------------------------------------------------------
    // Transfer the balance from token owner's account to `_to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transfer(address _to, uint256 _value) public returns (bool success);

    /* ERC20 Standard */
    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account
    // If this function is called again it overwrites the current allowance with _value.
    // 
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
    // recommends that there are no checks for the approval double-spend attack
    // as this should be implemented in user interfaces
    // ------------------------------------------------------------------------
    function approve(address _spender, uint256 _value) public returns (bool success);

    // ------------------------------------------------------------------------
    // Transfer `_value` from the `_from` account to the `_to` account
    //
    // The calling account must already have sufficient tokens approve(...)-d
    // for spending from the `from` account and
    // - From account must have sufficient balance to transfer
    // - Spender must have sufficient allowance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    // Triggered when tokens are transferred.
    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    // Triggered whenever approve(address _spender, uint256 _value) is called.
    event Approval(address indexed _tokenOwner, address indexed _spender, uint256 _value);

    /* Additional ERC20 Token Functionality */
    // ------------------------------------------------------------------------
    // Token owner can approve for `_spender` to transferFrom(...) `_value`
    // from the token owner's account. The `_spender` contract function
    // `receiveApproval(...)` is then executed
    // ------------------------------------------------------------------------
    function approveAndCall(address _spender, uint256 _value, bytes memory _data) public returns (bool success);

    // ------------------------------------------------------------------------
    // Don't accept ETH
    // ------------------------------------------------------------------------
    function () external payable;
 }

