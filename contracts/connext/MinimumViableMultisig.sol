pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@connext/contracts/src.sol/shared/libs/LibChannelCrypto.sol";
import "@connext/contracts/src.sol/shared/libs/LibCommitment.sol";

import "../staking/Staking.sol";

import "./MultisigData.sol";

/**
 * This file is excluded from ethlint/solium because of this issue:
 * https://github.com/duaraghav8/Ethlint/issues/261
 */

/// @title MinimumViableMultisig - A multisig wallet supporting the minimum
/// features required for state channels support
/// @author Liam Horne - <liam@l4v.io>
/// @notice
/// (a) Executes arbitrary transactions using `CALL` or `DELEGATECALL`
/// (b) Requires n-of-n unanimous consent
/// (c) Does not use on-chain address for signature verification
/// (d) Uses hash-based instead of nonce-based replay protection
contract MinimumViableMultisig is MultisigData, LibCommitment {
    using LibChannelCrypto for bytes32;

    mapping(bytes32 => bool) isExecuted;

    bool public locked;

    // Graph-specific constants
    address public NODE_ADDRESS;
    address public INDEXER_STAKING_ADDRESS;
    address public INDEXER_CTDT_ADDRESS;
    address public INDEXER_SINGLE_ASSET_INTERPRETER_ADDRESS;
    address public INDEXER_MULTI_ASSET_INTERPRETER_ADDRESS;
    address public INDEXER_WITHDRAW_INTERPRETER_ADDRESS;

    enum Operation { Call, DelegateCall }

    receive() external payable {}

    /// @notice Contract constructor (mastercopy)
    /// @param node Node signing address
    /// @param staking Address of the staking contract
    /// @param CTDT Address of indexer-specific CTDT contract
    /// @param singleAssetInterpreter Address of indexer-specific singleAssetInterpreter contract
    /// @param multiAssetInterpreter Address of indexer-specific multiAssetInterpreter contract
    /// @param withdrawInterpreter Address of indexer-specific withdrawInterpreter contract
    constructor(
        address node,
        address staking,
        address CTDT,
        address singleAssetInterpreter,
        address multiAssetInterpreter,
        address withdrawInterpreter
    ) public {
        NODE_ADDRESS = node;
        INDEXER_STAKING_ADDRESS = staking;
        INDEXER_CTDT_ADDRESS = CTDT;
        INDEXER_SINGLE_ASSET_INTERPRETER_ADDRESS = singleAssetInterpreter;
        INDEXER_MULTI_ASSET_INTERPRETER_ADDRESS = multiAssetInterpreter;
        INDEXER_WITHDRAW_INTERPRETER_ADDRESS = withdrawInterpreter;
    }

    /// @notice Contract constructor (proxy instance)
    /// @param owners An array of unique addresses representing the multisig owners
    function setup(address[] memory owners) public {
        require(_owners.length == 0, "Contract has been set up before");
        _owners = owners;
    }

    /// @notice Modifier to revert if caller is not staking contract
    modifier onlyStaking {
        require(
            msg.sender == MinimumViableMultisig(masterCopy).INDEXER_STAKING_ADDRESS(),
            "Caller must be the staking contract"
        );
        _;
    }

    /// @notice Lock the multisig; only the staking contract can do that.
    /// Locked node-indexer multisigs cannot execute transactions anymore.
    /// Regular multisigs are not affected by locking.
    function lock() external onlyStaking {
        // The following requirement can be removed if that is more suitable
        require(!locked, "Multisig must be unlocked to lock");

        locked = true;
    }

    /// @notice Execute an n-of-n signed transaction specified by a (to, value, data, op) tuple
    /// This transaction is a message call, i.e., either a CALL or a DELEGATECALL,
    /// depending on the value of `op`. The arguments `to`, `value`, `data` are passed
    /// as arguments to the CALL/DELEGATECALL.
    /// @param to The destination address of the message call
    /// @param value The amount of ETH being forwarded in the message call
    /// @param data Any calldata being sent along with the message call
    /// @param operation Specifies whether the message call is a `CALL` or a `DELEGATECALL`
    /// @param signatures A sorted bytes string of concatenated signatures of each owner
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        bytes[] memory signatures
    ) public {
        bytes32 transactionHash = getTransactionHash(to, value, data, operation);
        require(!isExecuted[transactionHash], "Transacation has already been executed");

        isExecuted[transactionHash] = true;

        for (uint256 i = 0; i < _owners.length; i++) {
            require(
                _owners[i] == transactionHash.verifyChannelMessage(signatures[i]),
                "Invalid signature"
            );
        }

        Staking staking = Staking(MinimumViableMultisig(masterCopy).INDEXER_STAKING_ADDRESS());
        address node = MinimumViableMultisig(masterCopy).NODE_ADDRESS();

        bool isNodeIndexerMultisig = _owners.length == 2 &&
            ((_owners[0] == node && staking.isChannel(_owners[1])) ||
                (_owners[1] == node && staking.isChannel(_owners[0])));

        if (isNodeIndexerMultisig) {
            require(!locked, "Node-indexer multisig must be unlocked to execute transactions");

            // Transactions from node-indexer multisigs get redirected to special CTDT contract
            execute(
                MinimumViableMultisig(masterCopy).INDEXER_CTDT_ADDRESS(),
                0,
                data,
                Operation.DelegateCall
            );
        } else {
            execute(to, value, data, operation);
        }
    }

    /// @notice Compute a unique transaction hash for a particular (to, value, data, op) tuple
    /// @return A unique hash that owners are expected to sign and submit to
    /// @notice Note that two transactions with identical values of (to, value, data, op)
    /// are not distinguished.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    uint8(CommitmentTarget.MULTISIG),
                    address(this),
                    to,
                    value,
                    keccak256(data),
                    uint8(operation)
                )
            );
    }

    /// @notice A getter function for the owners of the multisig
    /// @return An array of addresses representing the owners
    function getOwners() public view returns (address[] memory) {
        return _owners;
    }

    /// @notice Execute a transaction on behalf of the multisignature wallet
    function execute(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation
    ) internal {
        if (operation == Operation.Call) {
            require(executeCall(to, value, data), "executeCall failed");
        } else if (operation == Operation.DelegateCall) {
            require(executeDelegateCall(to, data), "executeDelegateCall failed");
        }
    }

    /// @notice Execute a CALL on behalf of the multisignature wallet
    /// @return success A boolean indicating if the transaction was successful or not
    function executeCall(
        address to,
        uint256 value,
        bytes memory data
    ) internal returns (bool success) {
        assembly {
            success := call(not(0), to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /// @notice Execute a DELEGATECALL on behalf of the multisignature wallet
    /// @return success A boolean indicating if the transaction was successful or not
    function executeDelegateCall(address to, bytes memory data) internal returns (bool success) {
        assembly {
            success := delegatecall(not(0), to, add(data, 0x20), mload(data), 0, 0)
        }
    }
}
