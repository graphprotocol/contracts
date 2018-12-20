pragma solidity ^0.5.1;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./BurnableERC20Token.sol";

// ----------------------------------------------------------------------------
// Burnable ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract GraphToken is
    Owned,
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
    
    /* Libraries */
    using SafeMath for uint256; // we explicitly use type uint256 even though uint is an alias for uint256

    /* STATE VARIABLES */
    // ------------------------------------------------------
    // Treasurers map to true
    mapping (address => bool) internal treasurers;
    // OR...
    // Single Treasurer (V1?)
    // address internal treasurer;
    // ------------------------------------------------------
 
    /* BurnableERC20Token Functions */
    // ------------------------------------------------------------------------
    // Total supply
    // ------------------------------------------------------------------------
    // Getter should have been created by the base contract
    // function totalSupply() public view returns (uint) {
    //     return totalSupply.sub(balances[address(0)]);
    // }


    // ------------------------------------------------------------------------
    // Get the token balance for account `tokenOwner`
    // ------------------------------------------------------------------------
    function balanceOf(address _tokenOwner) public view returns (uint balance) {
        return balances[_tokenOwner];
    }


    // ------------------------------------------------------------------------
    // Transfer the balance from token owner's account to `to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transfer(address _to, uint256 _value) public returns (bool success) {
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
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
    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
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
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/blob/9b3710465583284b8c4c5d2245749246bb2e0094/contracts/token/ERC20/ERC20.sol
        require(_value <= balances[_from]); // check balance
        require(_value <= allowed[_from][msg.sender]); // check allowance
        require(_to != address(0)); // address is good
        balances[_from] -= _value;
        balances[_to] += _value;
        allowed[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }


    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(address _tokenOwner, address _spender) public view returns (uint256 remaining) {
        return allowed[_tokenOwner][_spender];
    }


    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account. The `spender` contract function
    // `receiveApproval(...)` is then executed
    // ------------------------------------------------------------------------
    function approveAndCall(address _spender, uint256 _value, bytes memory _data) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        ApproveAndCallFallBack(_spender).receiveApproval(msg.sender, _value, address(this), _data);
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
    function transferAnyERC20Token(address _tokenAddress, uint256 _value) public onlyOwner returns (bool success) {
        return BurnableERC20Token(_tokenAddress).transfer(owner, _value);
    }

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
    
    /* Graph Token governed variables */
    // Set the total token supply
    function setTotalSupply(uint _newTotalSupply) external onlyOwner {
        totalSupply = _newTotalSupply;
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