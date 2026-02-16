// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for contracts that can act as authorized agreement approvers
 * @author Edge & Node
 * @notice Enables contracts to serve as authorized approvers in {Authorizable} and
 * {RecurringCollector}, replacing ECDSA signatures with on-chain callbacks.
 *
 * When a contract implements this interface:
 * - {Authorizable.authorizeSigner} calls {isAuthorizedSigner} instead of verifying an ECDSA proof
 * - {RecurringCollector.acceptFromContract} calls {isAuthorizedAgreement} instead of recovering an ECDSA signer
 *
 * Both functions use the magic-value pattern: return the function selector on success.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IContractApprover {
    /**
     * @notice Confirms this contract is willing to be authorized as signer for the given authorizer
     * @dev Called by {Authorizable.authorizeSigner} when the signer address has code.
     * The authorizer (msg.sender of authorizeSigner) is the payer delegating signing authority.
     * @param authorizer The address authorizing this contract as signer
     * @return magic `IContractApprover.isAuthorizedSigner.selector` if authorized
     */
    function isAuthorizedSigner(address authorizer) external view returns (bytes4);

    /**
     * @notice Confirms this contract authorized the creation of the given agreement
     * @dev Called by {RecurringCollector.acceptFromContract} to verify the contract
     * created and approved the specific RCA identified by its EIP712 hash.
     * @param agreementHash The EIP712 hash of the RecurringCollectionAgreement struct
     * @return magic `IContractApprover.isAuthorizedAgreement.selector` if authorized
     */
    function isAuthorizedAgreement(bytes32 agreementHash) external view returns (bytes4);
}
