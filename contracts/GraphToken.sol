pragma solidity ^0.5.2;
/*
 * @title GraphToken contract
 *
 * @author Bryant Eisenbach
 * @author Reuven Etzion
 *
 * Requirements
 * @req 01 The Graph Token shall implement the ERC20 Token Standard
 * @req 02 The Graph Token shall allow tokens staked in the protocol to be burned
 * @req 03 The Graph Token shall allow tokens to be minted to reward protocol participants
 * @req 04 The Graph Token shall only allow designated accounts the authority to mint
 *         Note: for example, the Payment Channel Hub and Rewards Manager contracts
 * @req 05 The Graph Token shall allow the protocol Governance to modify the accounts that have
 *         minting authority
 * @req 06 The Graph Token shall allow the protocol Governance to mint new tokens
 * @req 07 The Graph Token shall mint an inital distribution of tokens
 *
 */

import "./Governed.sol";
import "./openzeppelin/ERC20Burnable.sol";
import "./openzeppelin/ERC20Mintable.sol";
import "./openzeppelin/ERC20Detailed.sol";

contract GraphToken is
    Governed,
    ERC20Detailed, // @imp 01
    ERC20Burnable, // @imp 01, 02
    ERC20Mintable  // @imp 01, 03, 04
{
    // @imp 05, 06 Override so Governor can set Minters or mint tokens
    modifier onlyMinter() {
        require(isMinter(msg.sender) || msg.sender == governor);
        _;
    }
    
    /* 
     * @dev Init Graph Token contract
     * @param _governor <address> Address of the multisig contract as Governor of this contract
     * @param _initialSupply <uint256> Initial supply of Graph Tokens
     */
    constructor (address _governor, uint256 _initialSupply) public
        ERC20Detailed("Graph Token", "GRT", 18)
        Governed(_governor)
    {
        // @imp 06 Governor is initially the sole treasurer
        _addMinter(_governor);
        _removeMinter(msg.sender); // Zep automagically does this, so remove...

        // @imp 07 The Governer has the initial supply of tokens
        _mint(_governor, _initialSupply); // Deployment address holds all tokens

    }

    /**
     * @dev Method to expose `removeToken` while using the `onlyMinter` modifier
     * @param _account <address> Address of account to remove from `_minters`
     */
    function removeMinter(address _account) public onlyMinter {
        _removeMinter(_account);
    }

    // @dev Don't accept ETH
    function () external payable { revert(); }
}
