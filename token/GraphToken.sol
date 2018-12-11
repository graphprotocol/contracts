pragma solidity ^0.5.0;

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


contract GraphToken is BurnableERC20 {

    constructor () public {
        // ...
    }

}