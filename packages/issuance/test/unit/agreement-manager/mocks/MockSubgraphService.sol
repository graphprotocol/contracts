// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice Minimal mock of SubgraphService for ServiceAgreementManager cancelAgreement testing.
/// Records cancel calls and can be configured to revert.
contract MockSubgraphService {
    mapping(bytes16 => bool) public canceled;
    mapping(bytes16 => uint256) public cancelCallCount;

    bool public shouldRevert;
    string public revertMessage;

    function cancelIndexingAgreementByPayer(bytes16 agreementId) external {
        if (shouldRevert) {
            revert(revertMessage);
        }
        canceled[agreementId] = true;
        cancelCallCount[agreementId]++;
    }

    // -- Test helpers --

    function setRevert(bool _shouldRevert, string memory _message) external {
        shouldRevert = _shouldRevert;
        revertMessage = _message;
    }
}
