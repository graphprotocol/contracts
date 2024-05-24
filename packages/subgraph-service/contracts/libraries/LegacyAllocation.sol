// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

library LegacyAllocation {
    using LegacyAllocation for State;

    struct State {
        address indexer;
        bytes32 subgraphDeploymentID;
    }

    error LegacyAllocationExists(address allocationId);
    error LegacyAllocationDoesNotExist(address allocationId);
    error LegacyAllocationAlreadyMigrated(address allocationId);

    function migrate(
        mapping(address => State) storage self,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentID
    ) internal {
        require(!self[allocationId].exists(), LegacyAllocationExists(allocationId));

        State memory allocation = State({ indexer: indexer, subgraphDeploymentID: subgraphDeploymentID });
        self[allocationId] = allocation;
    }

    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

    function revertIfExists(mapping(address => State) storage self, address allocationId) internal view {
        require(!self[allocationId].exists(), LegacyAllocationExists(allocationId));
    }

    function exists(State memory self) internal pure returns (bool) {
        return self.indexer != address(0);
    }

    function _get(mapping(address => State) storage self, address allocationId) private view returns (State storage) {
        State storage allocation = self[allocationId];
        require(allocation.exists(), LegacyAllocationDoesNotExist(allocationId));
        return allocation;
    }
}
