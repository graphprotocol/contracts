// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

/**
 * @title TAPVerifier
 * @dev A contract for verifying receipt aggregation vouchers.
 */
contract TAPVerifier is ITAPVerifier, EIP712 {
    error TAPVerifierInvalidCaller(address sender, address expected);
    error TAPVerifierInvalidSignature();

    // --- EIP 712 ---
    bytes32 private constant RAV_TYPEHASH =
        keccak256("ReceiptAggregateVoucher(address allocationId,uint64 timestampNs,uint128 valueAggregate)");

    /**
     * @dev Constructs a new instance of the TAPVerifier contract.
     */
    constructor(string memory name, string memory version) EIP712(name, version) {}

    /**
     * @notice Verify validity of a SignedRAV
     * @dev Caller must be the data service the RAV was issued to.
     * @param signedRAV The SignedRAV containing the RAV and its signature.
     * @return The address of the signer.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function verify(SignedRAV calldata signedRAV) external view returns (address) {
        if (signedRAV.rav.dataService != msg.sender) {
            revert TAPVerifierInvalidCaller(msg.sender, signedRAV.rav.dataService);
        }
        address signer = recover(signedRAV);
        if (signer == address(0)) {
            revert TAPVerifierInvalidSignature();
        }
        return recover(signedRAV);
    }

    /**
     * @dev Recovers the signer address of a signed ReceiptAggregateVoucher (RAV).
     * @param signedRAV The SignedRAV containing the RAV and its signature.
     * @return The address of the signer.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function recover(SignedRAV calldata signedRAV) public view returns (address) {
        bytes32 messageHash = hash(signedRAV.rav);
        return ECDSA.recover(messageHash, signedRAV.signature);
    }

    /**
     * @dev Computes the hash of a ReceiptAggregateVoucher (RAV).
     * @param rav The RAV for which to compute the hash.
     * @return The hash of the RAV.
     */
    function hash(ReceiptAggregateVoucher calldata rav) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(RAV_TYPEHASH, rav.serviceProvider, rav.dataService, rav.timestampNs, rav.valueAggregate)
                )
            );
    }
}
