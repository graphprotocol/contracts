// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { MockGRTToken } from "./MockGRTToken.sol";

contract CurationMock {

    mapping(bytes32 => uint256) public curation;

    function signal(bytes32 _subgraphDeploymentID, uint256 _tokens) public {
        curation[_subgraphDeploymentID] += _tokens;
    }

    function isCurated(bytes32 _subgraphDeploymentID) public view returns (bool) {
        return curation[_subgraphDeploymentID] != 0;
    }

    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external {
        curation[_subgraphDeploymentID] += _tokens;
    }
}
