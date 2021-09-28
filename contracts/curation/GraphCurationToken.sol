// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../governance/Governed.sol";

/**
 * @title GraphCurationToken contract
 * @dev This is the implementation of the Curation ERC20 token (GCS).
 * GCS are created for each subgraph deployment curated in the Curation contract.
 * The Curation contract is the owner of GCS tokens and the only one allowed to mint or
 * burn them. GCS tokens are transferrable and their holders can do any action allowed
 * in a standard ERC20 token implementation except for burning them.
 */
contract GraphCurationToken is ERC20, Governed {
    /**
     * @dev Graph Curation Token Contract Constructor.
     * @param _owner Address of the contract issuing this token
     */
    constructor(address _owner) ERC20("Graph Curation Share", "GCS") {
        Governed._initialize(_owner);
    }

    /**
     * @dev Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) public onlyGovernor {
        _mint(_to, _amount);
    }

    /**
     * @dev Burn tokens from an address.
     * @param _account Address from where tokens will be burned
     * @param _amount Amount of tokens to burn
     */
    function burnFrom(address _account, uint256 _amount) public onlyGovernor {
        _burn(_account, _amount);
    }
}
