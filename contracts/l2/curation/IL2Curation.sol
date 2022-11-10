// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

interface IL2Curation {
    // Callable only by GNS in specific scenarios
    function mintTaxFree(
        bytes32 _subgraphDeploymentID,
        uint256 _tokensIn,
        uint256 _signalOutMin
    ) external returns (uint256);

    function tokensToSignalNoTax(bytes32 _subgraphDeploymentID, uint256 _tokensIn)
        external
        view
        returns (uint256);
}
