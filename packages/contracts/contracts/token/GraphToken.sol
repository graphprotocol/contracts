// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-small-strings, gas-strict-inequalities
// solhint-disable named-parameters-mapping

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { Governed } from "../governance/Governed.sol";

/**
 * @title GraphToken contract
 * @author Edge & Node
 * @notice This is the implementation of the ERC20 Graph Token.
 * The implementation exposes a Permit() function to allow for a spender to send a signed message
 * and approve funds to a spender following EIP2612 to make integration with other contracts easier.
 *
 * The token is initially owned by the deployer address that can mint tokens to create the initial
 * distribution. For convenience, an initial supply can be passed in the constructor that will be
 * assigned to the deployer.
 *
 * The governor can add the RewardsManager contract to mint indexing rewards.
 *
 */
contract GraphToken is Governed, ERC20, ERC20Burnable {
    using SafeMath for uint256;

    // -- EIP712 --
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#definition-of-domainseparator

    /// @dev EIP-712 domain type hash for signature verification
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    /// @dev EIP-712 domain name hash for signature verification
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Token");
    /// @dev EIP-712 domain version hash for signature verification
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    /// @dev EIP-712 domain salt for signature verification (randomly generated)
    bytes32 private constant DOMAIN_SALT = 0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa; // Randomly generated salt
    /// @dev EIP-712 permit typehash for signature verification
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // -- State --

    /// @dev EIP-712 domain separator for signature verification
    bytes32 private domainSeparator;
    /// @dev Mapping of addresses authorized to mint tokens
    mapping(address => bool) private _minters;
    /**
     * @notice Nonces for permit functionality (EIP-2612)
     * @dev Mapping from owner address to current nonce for permit signatures
     */
    mapping(address => uint256) public nonces;

    // -- Events --

    /**
     * @notice Emitted when a new minter is added
     * @param account Address of the minter that was added
     */
    event MinterAdded(address indexed account);

    /**
     * @notice Emitted when a minter is removed
     * @param account Address of the minter that was removed
     */
    event MinterRemoved(address indexed account);

    /// @dev Modifier to restrict access to minters only
    modifier onlyMinter() {
        require(isMinter(msg.sender), "Only minter can call");
        _;
    }

    /**
     * @notice Graph Token Contract Constructor.
     * @param _initialSupply Initial supply of GRT
     */
    constructor(uint256 _initialSupply) ERC20("Graph Token", "GRT") {
        Governed._initialize(msg.sender);

        // The Governor has the initial supply of tokens
        _mint(msg.sender, _initialSupply);

        // The Governor is the default minter
        _addMinter(msg.sender);

        // EIP-712 domain separator
        domainSeparator = keccak256(
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
     * @notice Approve token allowance by validating a message signed by the holder.
     * @param _owner Address of the token holder
     * @param _spender Address of the approved spender
     * @param _value Amount of tokens to approve the spender
     * @param _deadline Expiration time of the signed permit
     * @param _v Signature version
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
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, nonces[_owner], _deadline))
            )
        );
        nonces[_owner] = nonces[_owner].add(1);

        address recoveredAddress = ECDSA.recover(digest, abi.encodePacked(_r, _s, _v));
        require(_owner == recoveredAddress, "GRT: invalid permit");
        require(_deadline == 0 || block.timestamp <= _deadline, "GRT: expired permit");

        _approve(_owner, _spender, _value);
    }

    /**
     * @notice Add a new minter.
     * @param _account Address of the minter
     */
    function addMinter(address _account) external onlyGovernor {
        _addMinter(_account);
    }

    /**
     * @notice Remove a minter.
     * @param _account Address of the minter
     */
    function removeMinter(address _account) external onlyGovernor {
        _removeMinter(_account);
    }

    /**
     * @notice Renounce to be a minter.
     */
    function renounceMinter() external {
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
     * @notice Add a new minter.
     * @param _account Address of the minter
     */
    function _addMinter(address _account) private {
        _minters[_account] = true;
        emit MinterAdded(_account);
    }

    /**
     * @notice Remove a minter.
     * @param _account Address of the minter
     */
    function _removeMinter(address _account) private {
        _minters[_account] = false;
        emit MinterRemoved(_account);
    }

    /**
     * @notice Get the running network chain ID.
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
