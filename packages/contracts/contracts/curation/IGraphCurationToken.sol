// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title Graph Curation Token Interface
 * @author Edge & Node
 * @notice Interface for curation tokens that represent shares in subgraph curation pools
 */
interface IGraphCurationToken is IERC20Upgradeable {
    /**
     * @notice Graph Curation Token Contract initializer.
     * @param _owner Address of the contract issuing this token
     */
    function initialize(address _owner) external;

    /**
     * @notice Burn tokens from an address.
     * @param _account Address from where tokens will be burned
     * @param _amount Amount of tokens to burn
     */
    function burnFrom(address _account, uint256 _amount) external;

    /**
     * @notice Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external;
}
