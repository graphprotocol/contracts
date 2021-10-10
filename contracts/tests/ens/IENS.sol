pragma solidity ^0.7.6;

// Needed for abi and typechain in the npm package
interface IENS {
    function owner(bytes32 node) external view returns (address);

    // Must call setRecord, not setOwner, We must namehash it ourselves as well
    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address owner,
        address resolver,
        uint64 ttl
    ) external;
}
