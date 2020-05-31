pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";


/**
 * @title GraphToken contract
 * @dev This is the implementation of the ERC20 Graph Token.
 */
contract GraphToken is Governed, ERC20, ERC20Burnable {
    // -- EIP712 --

    bytes32 private constant DOMAIN_TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
    );
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Token");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT = 0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa;
    bytes32 private constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 nonce,uint256 expiry,bool allowed)"
    );

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
     * @param _governor Owner address of this contract
     * @param _initialSupply Initial supply of GRT
     */
    constructor(address _governor, uint256 _initialSupply)
        public
        ERC20("Graph Token", "GRT")
        Governed(_governor)
    {
        // The Governor has the initial supply of tokens
        _mint(_governor, _initialSupply);

        // The Governor is the default minter
        _addMinter(_governor);

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
     * This function will approve MAX_UINT256 tokens to be spent.
     * @param _owner Address of the token holder
     * @param _spender Address of the approved spender
     * @param _nonce Sequence number to avoid permit reuse
     * @param _expiry Expiration time of the signed permit
     * @param _allowed Whether to approve or dissaprove the spender
     * @param _v Signature version
     * @param _r Signature r value
     * @param _s Signature s value
     */
    function permit(
        address _owner,
        address _spender,
        uint256 _nonce,
        uint256 _expiry,
        bool _allowed,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _nonce, _expiry, _allowed))
            )
        );

        require(_owner == ecrecover(digest, _v, _r, _s), "GRT: invalid permit");
        require(_expiry == 0 || block.timestamp <= _expiry, "GRT: permit expired");
        require(_nonce == nonces[_owner]++, "GRT: invalid nonce");

        uint256 allowance = _allowed ? uint256(-1) : 0;
        _approve(_owner, _spender, allowance);
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
    function _addMinter(address _account) internal {
        _minters[_account] = true;
        emit MinterAdded(_account);
    }

    /**
     * @dev Remove a minter.
     * @param _account Address of the minter
     */
    function _removeMinter(address _account) internal {
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
