pragma solidity ^0.5.1;

import "./SafeMath.sol";
import "./Ownable.sol";

// ----------------------------------------------------------------------------
// ERC Token Standard #20 Abstract Contract / Interface
// https://github.com/ethereum/EIPs/issues/20
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
// ----------------------------------------------------------------------------
// Constructed according to OpenZeppelin Burnable Token contract
// https://github.com/OpenZeppelin/zeppelin-solidity/
contract BurnableERC20Token {

    /* ERC20 BASIC */
    // Get the total token supply
    function totalSupply() public view returns (uint);
    
    // Get the account balance of another account with address _owner
    function balanceOf(address tokenOwner) public view returns (uint balance);
    
    // Returns the amount which _spender is still allowed to withdraw from _owner
    function allowance(address tokenOwner, address spender) public view returns (uint remaining);

    // Send _value amount of tokens to address _to
    function transfer(address to, uint tokens) public returns (bool success);

    /* ERC20 Standard */
    // Allow _spender to withdraw from your account, multiple times, up to the _value amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve(address spender, uint tokens) public returns (bool success);

    // Send _value amount of tokens from address _from to address _to
    function transferFrom(address from, address to, uint tokens) public returns (bool success);

    // Triggered when tokens are transferred.
    event Transfer(address indexed from, address indexed to, uint tokens);

    // Triggered whenever approve(address _spender, uint256 _value) is called.
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
 
    /* BURNABLE ERC20 */
    // Burn _value amount of your own tokens
    function burn(uint256 value) public;

    // Triggered whenever burn(uint256 _value) is called
    event Burn(address indexed burner, uint256 value);
}

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------
contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public;
}


// ----------------------------------------------------------------------------
// Burnable ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract GraphToken is Owned, BurnableERC20Token {
    
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
    
    /* Libraries */
    using SafeMath for uint; // we use the uint alias for uint256

    /* Events */
    // Triggered when tokens are transferred.
    event Transfer(address indexed from, address indexed to, uint tokens);

    // Triggered whenever approve(address _spender, uint256 _value) is called.
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

    // Triggered whenever burn(uint256 _value) is called
    event Burn(address indexed burner, uint256 value);

    /* STATE VARIABLES */
    // Total supply of Graph Tokens

    // Token details
    string public symbol;
    string public  name;
    uint8 public decimals;
    uint _totalSupply;

    // Balances for each account
    mapping (address => uint) balances;
    
    // Owner of account approves the transfer of an amount to another account
    mapping (address => mapping (address => uint)) allowed;
    
    // Treasurers map to true
    mapping (address => bool) internal treasurers;
 
    /* BurnableERC20Token Functions */
    // ------------------------------------------------------------------------
    // Total supply
    // ------------------------------------------------------------------------
    function totalSupply() public view returns (uint) {
        return _totalSupply.sub(balances[address(0)]);
    }


    // ------------------------------------------------------------------------
    // Get the token balance for account `tokenOwner`
    // ------------------------------------------------------------------------
    function balanceOf(address tokenOwner) public view returns (uint balance) {
        return balances[tokenOwner];
    }


    // ------------------------------------------------------------------------
    // Transfer the balance from token owner's account to `to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transfer(address to, uint tokens) public returns (bool success) {
        balances[msg.sender] = balances[msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        emit Transfer(msg.sender, to, tokens);
        return true;
    }


    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account
    //
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
    // recommends that there are no checks for the approval double-spend attack
    // as this should be implemented in user interfaces
    // ------------------------------------------------------------------------
    function approve(address spender, uint tokens) public returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }


    // ------------------------------------------------------------------------
    // Transfer `tokens` from the `from` account to the `to` account
    //
    // The calling account must already have sufficient tokens approve(...)-d
    // for spending from the `from` account and
    // - From account must have sufficient balance to transfer
    // - Spender must have sufficient allowance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transferFrom(address from, address to, uint tokens) public returns (bool success) {
        balances[from] = balances[from].sub(tokens);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        emit Transfer(from, to, tokens);
        return true;
    }


    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(address tokenOwner, address spender) public view returns (uint remaining) {
        return allowed[tokenOwner][spender];
    }


    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account. The `spender` contract function
    // `receiveApproval(...)` is then executed
    // ------------------------------------------------------------------------
    function approveAndCall(address spender, uint tokens, bytes memory data) public returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, address(this), data);
        return true;
    }


    // ------------------------------------------------------------------------
    // Don't accept ETH
    // ------------------------------------------------------------------------
    function () external payable {
        revert();
    }


    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address tokenAddress, uint tokens) public onlyOwner returns (bool success) {
        return BurnableERC20Token(tokenAddress).transfer(owner, tokens);
    }

    // Burn _value amount of your own tokens
    function burn(uint256 value) public {
        // @TODO: check balance and burn tokens
    }

    
    /* Init Graph Token contract */
    constructor (uint _initialSupply) public {
        name = "The Graph Token"; // TODO: Confirm a name or lose this
        symbol = "TGT"; // TODO: Confirm a sybol or lose this
        decimals = 18;  // 18 is the most common number of decimal places
        _totalSupply = _initialSupply * 10**uint(decimals);
        balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);
    }
    
    /* Graph Token governed variables */
    // Set the total token supply
    function setTotalSupply(uint _newTotalSupply) external onlyOwner {
        _totalSupply = _newTotalSupply;
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