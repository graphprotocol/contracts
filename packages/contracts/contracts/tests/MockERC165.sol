// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;

import { IERC165 } from "@openzeppelin/contracts/introspection/IERC165.sol";

/**
 * @title MockERC165
 * @author Edge & Node
 * @dev Minimal implementation of IERC165 for testing
 * @notice Used to test interface validation - supports only ERC165, not specific interfaces
 */
contract MockERC165 is IERC165 {
    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
