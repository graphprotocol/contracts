pragma solidity ^0.5.1;

// ----------------------------------------------------------------------------
// Burnable ERC Token Standard #20 Abstract Contract / Interface
// ----------------------------------------------------------------------------
contract BurnableERC20Token {
    /* BURNABLE ERC20 */
    // Burn _value amount of your own tokens
    function burn(uint256 _value) public;

    // Triggered whenever burn(uint256 _value) is called
    event Burn(address indexed _burner, uint256 _value);
}
