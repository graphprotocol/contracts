// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title Graph Curation Token Interface
 * @author Edge & Node
 * @notice Interface for curation tokens that represent shares in subgraph curation pools
 */
interface IGraphCurationToken is IERC20Upgradeable {
    /**
     * @notice Graph Curation Token Contract initializer.
     * @param owner Address of the contract issuing this token
     */
    function initialize(address owner) external;

    /**
     * @notice Burn tokens from an address.
     * @param account Address from where tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @notice Mint new tokens.
     * @param to Address to send the newly minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;
}
