// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { ICallhookReceiver } from "./ICallhookReceiver.sol";
import { GraphTokenLockManager } from "./GraphTokenLockManager.sol";
import { L2GraphTokenLockWallet } from "./L2GraphTokenLockWallet.sol";

/**
 * @title L2GraphTokenLockManager
 * @notice This contract manages a list of authorized function calls and targets that can be called
 * by any TokenLockWallet contract and it is a factory of TokenLockWallet contracts.
 *
 * This contract receives funds to make the process of creating TokenLockWallet contracts
 * easier by distributing them the initial tokens to be managed.
 *
 * In particular, this L2 variant is designed to receive token lock wallets from L1,
 * through the GRT bridge. These transferred wallets will not allow releasing funds in L2 until
 * the end of the vesting timeline, but they can allow withdrawing funds back to L1 using
 * the L2GraphTokenLockTransferTool contract.
 *
 * The owner can setup a list of token destinations that will be used by TokenLock contracts to
 * approve the pulling of funds, this way in can be guaranteed that only protocol contracts
 * will manipulate users funds.
 */
contract L2GraphTokenLockManager is GraphTokenLockManager, ICallhookReceiver {
    using SafeERC20 for IERC20;

    /// @dev Struct to hold the data of a transferred wallet; this is
    /// the data that must be encoded in L1 to send a wallet to L2.
    struct TransferredWalletData {
        address l1Address;
        address owner;
        address beneficiary;
        uint256 managedAmount;
        uint256 startTime;
        uint256 endTime;
    }

    /// Address of the L2GraphTokenGateway
    address public immutable l2Gateway;
    /// Address of the L1 transfer tool contract (in L1, no aliasing)
    address public immutable l1TransferTool;
    /// Mapping of each L1 wallet to its L2 wallet counterpart (populated when each wallet is received)
    /// L1 address => L2 address
    mapping(address => address) public l1WalletToL2Wallet;
    /// Mapping of each L2 wallet to its L1 wallet counterpart (populated when each wallet is received)
    /// L2 address => L1 address
    mapping(address => address) public l2WalletToL1Wallet;

    /// @dev Event emitted when a wallet is received and created from L1
    event TokenLockCreatedFromL1(
        address indexed contractAddress,
        bytes32 initHash,
        address indexed beneficiary,
        uint256 managedAmount,
        uint256 startTime,
        uint256 endTime,
        address indexed l1Address
    );

    /// @dev Emitted when locked tokens are received from L1 (whether the wallet
    /// had already been received or not)
    event LockedTokensReceivedFromL1(address indexed l1Address, address indexed l2Address, uint256 amount);

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == l2Gateway, "ONLY_GATEWAY");
        _;
    }

    /**
     * @notice Constructor for the L2GraphTokenLockManager contract.
     * @param _graphToken Address of the L2 GRT token contract
     * @param _masterCopy Address of the master copy of the L2GraphTokenLockWallet implementation
     * @param _l2Gateway Address of the L2GraphTokenGateway contract
     * @param _l1TransferTool Address of the L1 transfer tool contract (in L1, without aliasing)
     */
    constructor(
        IERC20 _graphToken,
        address _masterCopy,
        address _l2Gateway,
        address _l1TransferTool
    ) GraphTokenLockManager(_graphToken, _masterCopy) {
        l2Gateway = _l2Gateway;
        l1TransferTool = _l1TransferTool;
    }

    /**
     * @notice This function is called by the L2GraphTokenGateway when tokens are sent from L1.
     * @dev This function will create a new wallet if it doesn't exist yet, or send the tokens to
     * the existing wallet if it does.
     * @param _from Address of the sender in L1, which must be the L1GraphTokenLockTransferTool
     * @param _amount Amount of tokens received
     * @param _data Encoded data of the transferred wallet, which must be an ABI-encoded TransferredWalletData struct
     */
    function onTokenTransfer(address _from, uint256 _amount, bytes calldata _data) external override onlyL2Gateway {
        require(_from == l1TransferTool, "ONLY_TRANSFER_TOOL");
        TransferredWalletData memory walletData = abi.decode(_data, (TransferredWalletData));

        if (l1WalletToL2Wallet[walletData.l1Address] != address(0)) {
            // If the wallet was already received, just send the tokens to the L2 address
            _token.safeTransfer(l1WalletToL2Wallet[walletData.l1Address], _amount);
        } else {
            // Create contract using a minimal proxy and call initializer
            (bytes32 initHash, address contractAddress) = _deployFromL1(keccak256(_data), walletData);
            l1WalletToL2Wallet[walletData.l1Address] = contractAddress;
            l2WalletToL1Wallet[contractAddress] = walletData.l1Address;

            // Send managed amount to the created contract
            _token.safeTransfer(contractAddress, _amount);

            emit TokenLockCreatedFromL1(
                contractAddress,
                initHash,
                walletData.beneficiary,
                walletData.managedAmount,
                walletData.startTime,
                walletData.endTime,
                walletData.l1Address
            );
        }
        emit LockedTokensReceivedFromL1(walletData.l1Address, l1WalletToL2Wallet[walletData.l1Address], _amount);
    }

    /**
     * @dev Deploy a token lock wallet with data received from L1
     * @param _salt Salt for the CREATE2 call, which must be the hash of the wallet data
     * @param _walletData Data of the wallet to be created
     * @return Hash of the initialization calldata
     * @return Address of the created contract
     */
    function _deployFromL1(
        bytes32 _salt,
        TransferredWalletData memory _walletData
    ) internal returns (bytes32, address) {
        bytes memory initializer = _encodeInitializer(_walletData);
        address contractAddress = _deployProxy2(_salt, masterCopy, initializer);
        return (keccak256(initializer), contractAddress);
    }

    /**
     * @dev Encode the initializer for the token lock wallet received from L1
     * @param _walletData Data of the wallet to be created
     * @return Encoded initializer calldata, including the function signature
     */
    function _encodeInitializer(TransferredWalletData memory _walletData) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                L2GraphTokenLockWallet.initializeFromL1.selector,
                address(this),
                address(_token),
                _walletData
            );
    }
}
