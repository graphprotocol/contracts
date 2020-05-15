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
    // -- State --

    mapping(address => bool) private _minters;

    // -- Events --

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);

    modifier onlyMinter() {
        require(isMinter(msg.sender), "Only minter can call");
        _;
    }

    /**
     * @dev Graph Token Contract Constructor
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
    }

    /**
     * @dev Add a new minter
     * @param _account Address of the minter
     */
    function addMinter(address _account) external onlyGovernor {
        _addMinter(_account);
    }

    /**
     * @dev Remove a minter
     * @param _account Address of the minter
     */
    function removeMinter(address _account) external onlyGovernor {
        _removeMinter(_account);
    }

    /**
     * @dev Renounce to be a minter
     */
    function renounceMinter() external {
        _removeMinter(msg.sender);
    }

    /**
     * @dev Mint new tokens
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    /**
     * @dev Return if the `_account` is a minter or not
     * @param _account Address to check
     * @return True if the `_account` is minter
     */
    function isMinter(address _account) public view returns (bool) {
        return _minters[_account];
    }

    /**
     * @dev Add a new minter
     * @param _account Address of the minter
     */
    function _addMinter(address _account) internal {
        _minters[_account] = true;
        emit MinterAdded(_account);
    }

    /**
     * @dev Remove a minter
     * @param _account Address of the minter
     */
    function _removeMinter(address _account) internal {
        _minters[_account] = false;
        emit MinterRemoved(_account);
    }
}
