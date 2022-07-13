// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../upgrades/GraphUpgradeable.sol";
import "../../token/GraphToken.sol";
import "../../arbitrum/IArbToken.sol";
import "../../governance/Governed.sol";

/**
 * @title GraphTokenUpgradeable contract
 * @dev This is the implementation of the ERC20 Graph Token.
 * The implementation exposes a Permit() function to allow for a spender to send a signed message
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
contract GraphTokenUpgradeable is
    GraphUpgradeable,
    Governed,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable
{
    using SafeMath for uint256;

    // -- EIP712 --
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#definition-of-domainseparator

    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
        );
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Token");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT =
        0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591; // Randomly generated salt
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // -- State --

    // solhint-disable-next-line var-name-mixedcase
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
     * @dev Approve token allowance by validating a message signed by the holder.
     * @param _owner Address of the token holder
     * @param _spender Address of the approved spender
     * @param _value Amount of tokens to approve the spender
     * @param _deadline Expiration time of the signed permit (if zero, the permit will never expire, so use with caution)
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
                keccak256(
                    abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, nonces[_owner], _deadline)
                )
            )
        );

        address recoveredAddress = ECDSA.recover(digest, _v, _r, _s);
        require(_owner == recoveredAddress, "GRT: invalid permit");
        require(_deadline == 0 || block.timestamp <= _deadline, "GRT: expired permit");

        nonces[_owner] = nonces[_owner].add(1);
        _approve(_owner, _spender, _value);
    }

    /**
     * @dev Add a new minter.
     * @param _account Address of the minter
     */
    function addMinter(address _account) external onlyGovernor {
        require(_account != address(0), "INVALID_MINTER");
        _addMinter(_account);
    }

    /**
     * @dev Remove a minter.
     * @param _account Address of the minter
     */
    function removeMinter(address _account) external onlyGovernor {
        require(_minters[_account], "NOT_A_MINTER");
        _removeMinter(_account);
    }

    /**
     * @dev Renounce to be a minter.
     */
    function renounceMinter() external {
        require(_minters[msg.sender], "NOT_A_MINTER");
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
     * @dev Graph Token Contract initializer.
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

/**
 * @title L2 Graph Token Contract
 * @dev Provides the L2 version of the GRT token, meant to be minted/burned
 * through the L2GraphTokenGateway.
 */
contract L2GraphToken is GraphTokenUpgradeable, IArbToken {
    using SafeMath for uint256;

    // Address of the gateway (on L2) that is allowed to mint tokens
    address public gateway;
    // Address of the corresponding Graph Token contract on L1
    address public override l1Address;

    // Emitted when the bridge / gateway has minted new tokens, i.e. tokens were transferred to L2
    event BridgeMinted(address indexed account, uint256 amount);
    // Emitted when the bridge / gateway has burned tokens, i.e. tokens were transferred back to L1
    event BridgeBurned(address indexed account, uint256 amount);
    // Emitted when the address of the gateway has been updated
    event GatewaySet(address gateway);
    // Emitted when the address of the Graph Token contract on L1 has been updated
    event L1AddressSet(address l1Address);

    /**
     * @dev Checks that the sender is the L2 gateway from the L1/L2 token bridge
     */
    modifier onlyGateway() {
        require(msg.sender == gateway, "NOT_GATEWAY");
        _;
    }

    /**
     * @dev L2 Graph Token Contract initializer.
     * @param _owner Governance address that owns this contract
     */
    function initialize(address _owner) external onlyImpl {
        require(_owner != address(0), "Owner must be set");
        // Initial supply hard coded to 0 as tokens are only supposed
        // to be minted through the bridge.
        GraphTokenUpgradeable._initialize(_owner, 0);
    }

    /**
     * @dev Sets the address of the L2 gateway allowed to mint tokens
     */
    function setGateway(address _gw) external onlyGovernor {
        require(_gw != address(0), "INVALID_GATEWAY");
        gateway = _gw;
        emit GatewaySet(gateway);
    }

    /**
     * @dev Sets the address of the counterpart token on L1
     */
    function setL1Address(address _addr) external onlyGovernor {
        require(_addr != address(0), "INVALID_L1_ADDRESS");
        l1Address = _addr;
        emit L1AddressSet(_addr);
    }

    /**
     * @dev Increases token supply, only callable by the L1/L2 bridge (when tokens are transferred to L2)
     * @param _account Address to credit with the new tokens
     * @param _amount Number of tokens to mint
     */
    function bridgeMint(address _account, uint256 _amount) external override onlyGateway {
        _mint(_account, _amount);
        emit BridgeMinted(_account, _amount);
    }

    /**
     * @dev Decreases token supply, only callable by the L1/L2 bridge (when tokens are transferred to L1).
     * @param _account Address from which to extract the tokens
     * @param _amount Number of tokens to burn
     */
    function bridgeBurn(address _account, uint256 _amount) external override onlyGateway {
        burnFrom(_account, _amount);
        emit BridgeBurned(_account, _amount);
    }
}
