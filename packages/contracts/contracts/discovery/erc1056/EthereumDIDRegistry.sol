/*
Original Author: https://github.com/uport-project/ethr-did-registry

This contract is included in graphprotocol/contracts for testing purposes
The contract is already deployed on mainnet:
https://etherscan.io/address/0xdca7ef03e98e0dc2b855be647c39abe984fcf21b#code

As well as all testnets
*/

// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one, gas-indexed-events, gas-small-strings

/**
 * @title Ethereum DID Registry
 * @author Edge & Node
 * @notice Registry for Ethereum Decentralized Identifiers (DIDs)
 */
contract EthereumDIDRegistry {
    /// @notice Mapping of identity addresses to their owners
    mapping(address => address) public owners;
    /// @notice Mapping of identity addresses to delegate types to delegate addresses to validity periods
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public delegates;
    /// @notice Mapping of identity addresses to their last change block numbers
    mapping(address => uint256) public changed;
    /// @notice Mapping of identity addresses to their nonce values
    mapping(address => uint256) public nonce;

    /**
     * @notice Modifier to restrict access to identity owners only
     * @param identity The identity address
     * @param actor The address performing the action
     */
    modifier onlyOwner(address identity, address actor) {
        require(actor == identityOwner(identity), "Caller must be the identity owner");
        _;
    }

    /**
     * @notice Emitted when a DID owner is changed
     * @param identity The identity address
     * @param owner The new owner address
     * @param previousChange Block number of the previous change
     */
    event DIDOwnerChanged(address indexed identity, address owner, uint256 previousChange);

    /**
     * @notice Emitted when a DID delegate is changed
     * @param identity The identity address
     * @param delegateType The type of delegate
     * @param delegate The delegate address
     * @param validTo Timestamp until which the delegate is valid
     * @param previousChange Block number of the previous change
     */
    event DIDDelegateChanged(
        address indexed identity,
        bytes32 delegateType,
        address delegate,
        uint256 validTo,
        uint256 previousChange
    );

    /**
     * @notice Emitted when a DID attribute is changed
     * @param identity The identity address
     * @param name The attribute name
     * @param value The attribute value
     * @param validTo Timestamp until which the attribute is valid
     * @param previousChange Block number of the previous change
     */
    event DIDAttributeChanged(
        address indexed identity,
        bytes32 name,
        bytes value,
        uint256 validTo,
        uint256 previousChange
    );

    /**
     * @notice Get the owner of an identity
     * @param identity The identity address
     * @return The address of the identity owner
     */
    function identityOwner(address identity) public view returns (address) {
        address owner = owners[identity];
        if (owner != address(0)) {
            return owner;
        }
        return identity;
    }

    /**
     * @notice Verify signature and return signer address
     * @param identity The identity address
     * @param sigV Recovery ID of the signature
     * @param sigR R component of the signature
     * @param sigS S component of the signature
     * @param hash Hash that was signed
     * @return The address of the signer
     */
    function checkSignature(
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS,
        bytes32 hash
    ) internal returns (address) {
        address signer = ecrecover(hash, sigV, sigR, sigS);
        require(signer == identityOwner(identity), "Signer must be the identity owner");
        nonce[signer]++;
        return signer;
    }

    /**
     * @notice Check if a delegate is valid for an identity
     * @param identity The identity address
     * @param delegateType The type of delegate
     * @param delegate The delegate address
     * @return True if the delegate is valid, false otherwise
     */
    function validDelegate(address identity, bytes32 delegateType, address delegate) public view returns (bool) {
        uint256 validity = delegates[identity][keccak256(abi.encode(delegateType))][delegate];
        /* solium-disable-next-line security/no-block-members*/
        return (validity > block.timestamp);
    }

    /**
     * @notice Internal function to change the owner of an identity
     * @param identity The identity address
     * @param actor The address performing the action
     * @param newOwner The new owner address
     */
    function changeOwner(address identity, address actor, address newOwner) internal onlyOwner(identity, actor) {
        owners[identity] = newOwner;
        emit DIDOwnerChanged(identity, newOwner, changed[identity]);
        changed[identity] = block.number;
    }

    /**
     * @notice Change the owner of an identity
     * @param identity The identity address
     * @param newOwner The new owner address
     */
    function changeOwner(address identity, address newOwner) public {
        changeOwner(identity, msg.sender, newOwner);
    }

    /**
     * @notice Change the owner of an identity using a signed message
     * @param identity The identity address
     * @param sigV Recovery ID of the signature
     * @param sigR R component of the signature
     * @param sigS S component of the signature
     * @param newOwner The new owner address
     */
    function changeOwnerSigned(address identity, uint8 sigV, bytes32 sigR, bytes32 sigS, address newOwner) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0),
                this,
                nonce[identityOwner(identity)],
                identity,
                "changeOwner",
                newOwner
            )
        );
        changeOwner(identity, checkSignature(identity, sigV, sigR, sigS, hash), newOwner);
    }

    /**
     * @notice Internal function to add a delegate for an identity
     * @param identity The identity address
     * @param actor The address performing the action
     * @param delegateType The type of delegate
     * @param delegate The delegate address
     * @param validity The validity period in seconds
     */
    function addDelegate(
        address identity,
        address actor,
        bytes32 delegateType,
        address delegate,
        uint256 validity
    ) internal onlyOwner(identity, actor) {
        /* solium-disable-next-line security/no-block-members*/
        delegates[identity][keccak256(abi.encode(delegateType))][delegate] = block.timestamp + validity;
        emit DIDDelegateChanged(
            identity,
            delegateType,
            delegate,
            /* solium-disable-next-line security/no-block-members*/
            block.timestamp + validity,
            changed[identity]
        );
        changed[identity] = block.number;
    }

    /**
     * @notice Add a delegate for an identity
     * @param identity The identity to add a delegate for
     * @param delegateType The type of delegate
     * @param delegate The address of the delegate
     * @param validity The validity period in seconds
     */
    function addDelegate(address identity, bytes32 delegateType, address delegate, uint256 validity) public {
        addDelegate(identity, msg.sender, delegateType, delegate, validity);
    }

    /**
     * @notice Add a delegate for an identity using a signed message
     * @param identity The identity to add a delegate for
     * @param sigV The recovery id of the signature
     * @param sigR The r component of the signature
     * @param sigS The s component of the signature
     * @param delegateType The type of delegate
     * @param delegate The address of the delegate
     * @param validity The validity period in seconds
     */
    function addDelegateSigned(
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS,
        bytes32 delegateType,
        address delegate,
        uint256 validity
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0),
                this,
                nonce[identityOwner(identity)],
                identity,
                "addDelegate",
                delegateType,
                delegate,
                validity
            )
        );
        addDelegate(identity, checkSignature(identity, sigV, sigR, sigS, hash), delegateType, delegate, validity);
    }

    /**
     * @notice Internal function to revoke a delegate for an identity
     * @param identity The identity address
     * @param actor The address performing the action
     * @param delegateType The type of delegate
     * @param delegate The delegate address
     */
    function revokeDelegate(
        address identity,
        address actor,
        bytes32 delegateType,
        address delegate
    ) internal onlyOwner(identity, actor) {
        /* solium-disable-next-line security/no-block-members*/
        delegates[identity][keccak256(abi.encode(delegateType))][delegate] = block.timestamp;
        /* solium-disable-next-line security/no-block-members*/
        emit DIDDelegateChanged(identity, delegateType, delegate, block.timestamp, changed[identity]);
        changed[identity] = block.number;
    }

    /**
     * @notice Revoke a delegate for an identity
     * @param identity The identity to revoke a delegate for
     * @param delegateType The type of delegate
     * @param delegate The address of the delegate
     */
    function revokeDelegate(address identity, bytes32 delegateType, address delegate) public {
        revokeDelegate(identity, msg.sender, delegateType, delegate);
    }

    /**
     * @notice Revoke a delegate for an identity using a signed message
     * @param identity The identity to revoke a delegate for
     * @param sigV The recovery id of the signature
     * @param sigR The r component of the signature
     * @param sigS The s component of the signature
     * @param delegateType The type of delegate
     * @param delegate The address of the delegate
     */
    function revokeDelegateSigned(
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS,
        bytes32 delegateType,
        address delegate
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0),
                this,
                nonce[identityOwner(identity)],
                identity,
                "revokeDelegate",
                delegateType,
                delegate
            )
        );
        revokeDelegate(identity, checkSignature(identity, sigV, sigR, sigS, hash), delegateType, delegate);
    }

    /**
     * @notice Internal function to set an attribute for an identity
     * @param identity The identity address
     * @param actor The address performing the action
     * @param name The attribute name
     * @param value The attribute value
     * @param validity The validity period in seconds
     */
    function setAttribute(
        address identity,
        address actor,
        bytes32 name,
        bytes memory value,
        uint256 validity
    ) internal onlyOwner(identity, actor) {
        /* solium-disable-next-line security/no-block-members*/
        emit DIDAttributeChanged(identity, name, value, block.timestamp + validity, changed[identity]);
        changed[identity] = block.number;
    }

    /**
     * @notice Set an attribute for an identity
     * @param identity The identity to set an attribute for
     * @param name The name of the attribute
     * @param value The value of the attribute
     * @param validity The validity period in seconds
     */
    function setAttribute(address identity, bytes32 name, bytes memory value, uint256 validity) public {
        setAttribute(identity, msg.sender, name, value, validity);
    }

    /**
     * @notice Set an attribute for an identity using a signed message
     * @param identity The identity to set an attribute for
     * @param sigV The recovery id of the signature
     * @param sigR The r component of the signature
     * @param sigS The s component of the signature
     * @param name The name of the attribute
     * @param value The value of the attribute
     * @param validity The validity period in seconds
     */
    function setAttributeSigned(
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS,
        bytes32 name,
        bytes memory value,
        uint256 validity
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0),
                this,
                nonce[identityOwner(identity)],
                identity,
                "setAttribute",
                name,
                value,
                validity
            )
        );
        setAttribute(identity, checkSignature(identity, sigV, sigR, sigS, hash), name, value, validity);
    }

    /**
     * @notice Internal function to revoke an attribute for an identity
     * @param identity The identity address
     * @param actor The address performing the action
     * @param name The attribute name
     * @param value The attribute value
     */
    function revokeAttribute(
        address identity,
        address actor,
        bytes32 name,
        bytes memory value
    ) internal onlyOwner(identity, actor) {
        emit DIDAttributeChanged(identity, name, value, 0, changed[identity]);
        changed[identity] = block.number;
    }

    /**
     * @notice Revoke an attribute for an identity
     * @param identity The identity to revoke an attribute for
     * @param name The name of the attribute
     * @param value The value of the attribute
     */
    function revokeAttribute(address identity, bytes32 name, bytes memory value) public {
        revokeAttribute(identity, msg.sender, name, value);
    }

    /**
     * @notice Revoke an attribute for an identity using a signed message
     * @param identity The identity to revoke an attribute for
     * @param sigV The recovery id of the signature
     * @param sigR The r component of the signature
     * @param sigS The s component of the signature
     * @param name The name of the attribute
     * @param value The value of the attribute
     */
    function revokeAttributeSigned(
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS,
        bytes32 name,
        bytes memory value
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0),
                this,
                nonce[identityOwner(identity)],
                identity,
                "revokeAttribute",
                name,
                value
            )
        );
        revokeAttribute(identity, checkSignature(identity, sigV, sigR, sigS, hash), name, value);
    }
}
