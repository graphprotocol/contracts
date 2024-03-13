// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../governance/Governed.sol";

/**
 * @title GraphToken contract
 * @dev This is the implementation of the ERC20 Graph Token.
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

    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Token");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT = 0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa; // Randomly generated salt
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // -- State --

    bytes32 private DOMAIN_SEPARATOR;
    mapping(address => bool) private _minters;
    mapping(address => uint256) public nonces;

    // -- Events --

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);

    modifier onlyMinter() {
        require(isMinter(msg.sender), "Only minter can call");
        _;
    }

    /**
     * @dev Graph Token Contract Constructor.
     * @param _initialSupply Initial supply of GRT
     */
    constructor(uint256 _initialSupply) ERC20("Graph Token", "GRT") {
        Governed._initialize(msg.sender);

        // The Governor has the initial supply of tokens
        _mint(msg.sender, _initialSupply);

        // The Governor is the default minter
        _addMinter(msg.sender);

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
     * @dev Approve token allowance by validating a message signed by the holder.
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
                DOMAIN_SEPARATOR,
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
     * @dev Add a new minter.
     * @param _account Address of the minter
     */
    function addMinter(address _account) external onlyGovernor {
        _addMinter(_account);
    }

    /**
     * @dev Remove a minter.
     * @param _account Address of the minter
     */
    function removeMinter(address _account) external onlyGovernor {
        _removeMinter(_account);
    }

    /**
     * @dev Renounce to be a minter.
     */
    function renounceMinter() external {
        _removeMinter(msg.sender);
    }

    /**
     * @dev Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    /**
     * @dev Return if the `_account` is a minter or not.
     * @param _account Address to check
     * @return True if the `_account` is minter
     */
    function isMinter(address _account) public view returns (bool) {
        return _minters[_account];
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
        assembly {
            id := chainid()
        }
        return id;
    }
}
