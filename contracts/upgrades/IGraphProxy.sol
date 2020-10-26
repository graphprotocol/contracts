pragma solidity ^0.7.3;

interface IGraphProxy {
    function admin() external view returns (address);

    function setAdmin(address _newAdmin) external;

    function implementation() external view returns (address);

    function pendingImplementation() external view returns (address);

    function upgradeTo(address _newImplementation) external;

    function acceptUpgrade() external;
}
