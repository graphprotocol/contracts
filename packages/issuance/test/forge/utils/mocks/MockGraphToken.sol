// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockGraphToken
 * @notice A simplified version of GraphToken for testing purposes
 */
contract MockGraphToken is ERC20 {
    // State variables
    address public governor;
    mapping(address => bool) public minters;
    
    // Events
    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    
    /**
     * @notice Constructor
     * @param _governor Address of the governor
     */
    constructor(address _governor) ERC20("Graph Token", "GRT") {
        governor = _governor;
        minters[_governor] = true;
        emit MinterAdded(_governor);
    }
    
    /**
     * @notice Modifier to check if the caller is the governor
     */
    modifier onlyGovernor() {
        require(msg.sender == governor, "Only governor can call");
        _;
    }
    
    /**
     * @notice Modifier to check if the caller is a minter
     */
    modifier onlyMinter() {
        require(minters[msg.sender], "Only minter can call");
        _;
    }
    
    /**
     * @notice Add a minter
     * @param _account Address of the minter
     */
    function addMinter(address _account) external onlyGovernor {
        minters[_account] = true;
        emit MinterAdded(_account);
    }
    
    /**
     * @notice Remove a minter
     * @param _account Address of the minter
     */
    function removeMinter(address _account) external onlyGovernor {
        minters[_account] = false;
        emit MinterRemoved(_account);
    }
    
    /**
     * @notice Mint tokens
     * @param _to Address to mint tokens to
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }
    
    /**
     * @notice Burn tokens
     * @param _amount Amount of tokens to burn
     */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
    
    /**
     * @notice Burn tokens from an account
     * @param _from Address to burn tokens from
     * @param _amount Amount of tokens to burn
     */
    function burnFrom(address _from, uint256 _amount) external {
        uint256 currentAllowance = allowance(_from, msg.sender);
        require(currentAllowance >= _amount, "ERC20: burn amount exceeds allowance");
        _approve(_from, msg.sender, currentAllowance - _amount);
        _burn(_from, _amount);
    }
    
    /**
     * @notice Check if an account is a minter
     * @param _account Address to check
     * @return True if the account is a minter
     */
    function isMinter(address _account) external view returns (bool) {
        return minters[_account];
    }
}
