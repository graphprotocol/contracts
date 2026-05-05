// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mintable ERC20 standing in for the real GraphToken.
/// The real GraphToken is an ERC20 behind a proxy; this mock uses bare ERC20
/// which is slightly cheaper per call. The gas delta is small (~2-5k per call).
contract GraphTokenMock is ERC20 {
    constructor() ERC20("Graph Token", "GRT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Matches the GraphToken burn interface (self-burn).
    function burnFrom(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
