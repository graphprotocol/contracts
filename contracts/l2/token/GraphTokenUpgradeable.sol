// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { ERC20BurnableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20BurnableUpgradeable.sol";
import { ECDSAUpgradeable } from "@openzeppelin/contracts-upgradeable/cryptography/ECDSAUpgradeable.sol";

import { GraphUpgradeable } from "../../upgrades/GraphUpgradeable.sol";
import { Governed } from "../../governance/Governed.sol";

/**
 * @title GraphTokenUpgradeable contract
 * @dev This is the implementation of the ERC20 Graph Token.
 * The implementation exposes a permit() function to allow for a spender to send a signed message
 * and approve funds to a spender following EIP2612 to make integration with other contracts easier.
 *
 * The token is initially owned by the deployer address that can mint tokens to create the initial
 * distribution. For convenience, an initial supply can be passed in the constructor that will be
 * assigned to the deployer.
 *
 * The governor can add contracts allowed to mint indexing rewards.
 *
 * Note this is an exact copy of the original GraphToken contract, but using
 * initializer functions and upgradeable OpenZeppelin contracts instead of
 * the original's constructor + non-upgradeable approach.
 */
abstract contract GraphTokenUpgradeable is GraphUpgradeable, Governed, ERC20BurnableUpgradeable {
    // -- EIP712 --
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#definition-of-domainseparator

    /// @dev Hash of the EIP-712 Domain type
    bytes32 private immutable DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
        );
    /// @dev Hash of the EIP-712 Domain name
    bytes32 private immutable DOMAIN_NAME_HASH = keccak256("Graph Token");
    /// @dev Hash of the EIP-712 Domain version
    bytes32 private immutable DOMAIN_VERSION_HASH = keccak256("0");
    /// @dev EIP-712 Domain salt
    bytes32 private immutable DOMAIN_SALT =
        0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591; // Randomly generated salt
    /// @dev Hash of the EIP-712 permit type
    bytes32 private immutable PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // -- State --

    /// @dev EIP-712 Domain separator
    bytes32 private DOMAIN_SEPARATOR; // solhint-disable-line var-name-mixedcase
    /// @dev Addresses for which this mapping is true are allowed to mint tokens
    mapping(address => bool) private _minters;
    /// Nonces for permit signatures for each token holder
    mapping(address => uint256) public nonces;
    /// @dev Storage gap added in case we need to add state variables to this contract
    uint256[47] private __gap;

    // -- Events --

    /// Emitted when a new minter is added
    event MinterAdded(address indexed account);
    /// Emitted when a minter is removed
    event MinterRemoved(address indexed account);

    /// @dev Reverts if the caller is not an authorized minter
    modifier onlyMinter() {
        require(isMinter(msg.sender), "Only minter can call");
        _;
    }

    /**
     * @notice Approve token allowance by validating a message signed by the holder.
     * @param _owner Address of the token holder
     * @param _spender Address of the approved spender
     * @param _value Amount of tokens to approve the spender
     * @param _deadline Expiration time of the signed permit (if zero, the permit will never expire, so use with caution)
     * @param _v Signature recovery id
     * @param _r Signature r value
     * @param _s Signature s value
     */
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        require(_deadline == 0 || block.timestamp <= _deadline, "GRT: expired permit");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, nonces[_owner], _deadline)
                )
            )
        );

        address recoveredAddress = ECDSAUpgradeable.recover(digest, _v, _r, _s);
        require(_owner == recoveredAddress, "GRT: invalid permit");

        nonces[_owner] = nonces[_owner] + 1;
        _approve(_owner, _spender, _value);
    }

    /**
     * @notice Add a new minter.
     * @param _account Address of the minter
     */
    function addMinter(address _account) external onlyGovernor {
        require(_account != address(0), "INVALID_MINTER");
        _addMinter(_account);
    }

    /**
     * @notice Remove a minter.
     * @param _account Address of the minter
     */
    function removeMinter(address _account) external onlyGovernor {
        require(isMinter(_account), "NOT_A_MINTER");
        _removeMinter(_account);
    }

    /**
     * @notice Renounce being a minter.
     */
    function renounceMinter() external {
        require(isMinter(msg.sender), "NOT_A_MINTER");
        _removeMinter(msg.sender);
    }

    /**
     * @notice Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    /**
     * @notice Return if the `_account` is a minter or not.
     * @param _account Address to check
     * @return True if the `_account` is minter
     */
    function isMinter(address _account) public view returns (bool) {
        return _minters[_account];
    }

    /**
     * @dev Graph Token Contract initializer.
     * @param _owner Owner of this contract, who will hold the initial supply and will be a minter
     * @param _initialSupply Initial supply of GRT
     */
    function _initialize(address _owner, uint256 _initialSupply) internal {
        __ERC20_init("Graph Token", "GRT");
        Governed._initialize(_owner);

        // The Governor has the initial supply of tokens
        _mint(_owner, _initialSupply);

        // The Governor is the default minter
        _addMinter(_owner);

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                DOMAIN_NAME_HASH,
                DOMAIN_VERSION_HASH,
                _getChainID(),
                address(this),
                DOMAIN_SALT
            )
        );
    }

    /**
     * @dev Add a new minter.
     * @param _account Address of the minter
     */
    function _addMinter(address _account) private {
        _minters[_account] = true;
        emit MinterAdded(_account);
    }

    /**
     * @dev Remove a minter.
     * @param _account Address of the minter
     */
    function _removeMinter(address _account) private {
        _minters[_account] = false;
        emit MinterRemoved(_account);
    }

    /**
     * @dev Get the running network chain ID.
     * @return The chain ID
     */
    function _getChainID() private pure returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }
}
