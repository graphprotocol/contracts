// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IGraphCurationTokenLike {
    function initialize(address owner) external;

    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function governor() external view returns (address);
}
