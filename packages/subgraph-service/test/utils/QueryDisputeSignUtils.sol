// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/disputes/IDisputeManager.sol";

contract QueryDisputeSignUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    bytes32 public constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;
    bytes32 private constant RECEIPT_TYPE_HASH =
        keccak256("Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphDeploymentID)");

    constructor(address verifier) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH, DOMAIN_NAME_HASH, DOMAIN_VERSION_HASH, _getChainID(), verifier, DOMAIN_SALT
            )
        );
    }

    function getReceiptDataHash(IDisputeManager.Receipt memory _receipt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                RECEIPT_TYPE_HASH,
                _receipt.requestCID,
                _receipt.responseCID,
                _receipt.subgraphDeploymentID
            )
        );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getMessageHash(IDisputeManager.Receipt memory _receipt)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getReceiptDataHash(_receipt)
                )
            );
    }

    function _getChainID() private view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
}