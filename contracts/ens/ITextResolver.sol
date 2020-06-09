pragma solidity ^0.6.4;

interface ITextResolver {
    function text(bytes32 node, string calldata key) external view returns (string memory);
}
