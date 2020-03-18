pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title GraphToken contract
 *
 */

import "./Governed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

// @imp 08 target _to of transfer(_to, _amount, _data) in Token must implement this interface
// NOTE: This is based off of ERC777TokensRecipient interface, but does not fully implement it
interface TokenReceiver {
    function tokensReceived(
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool);
}

contract GraphToken is Governed, ERC20Detailed, ERC20Burnable {
    mapping(address => bool) private _minters;

    // -- Events --
    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);

    modifier onlyMinter() {
        require(
            isMinter(msg.sender) || msg.sender == governor,
            "Only minter can call"
        );
        _;
    }

    /*
     * @dev Init Graph Token contract
     * @param _governor <address> Address of the multisig contract as Governor of this contract
     * @param _initialSupply <uint256> Initial supply of Graph Tokens
     */
    constructor(address _governor, uint256 _initialSupply)
        public
        ERC20Detailed("Graph Token", "GRT", 18)
        Governed(_governor)
    {
        // Governor is initially the sole treasurer
        _addMinter(_governor);

        // The Governor has the initial supply of tokens
        _mint(_governor, _initialSupply);
    }

    function addMinter(address _account) external onlyGovernance {
        _addMinter(_account);
    }

    function removeMinter(address _account) external onlyGovernance {
        _removeMinter(_account);
    }

    function isMinter(address _account) public view returns (bool) {
        return _minters[_account];
    }

    function renounceMinter() external {
        _removeMinter(msg.sender);
    }

    function mint(address _account, uint256 _amount)
        external
        onlyMinter
        returns (bool)
    {
        _mint(_account, _amount);
        return true;
    }

    /*
     * @dev Transfer Graph tokens to the Staking interface
     * @notice Interacts with Staking contract
     * @notice Overriding `transfer` was not working with web3.js so we renamed to `transferToTokenReceiver`
     */
    function transferToTokenReceiver(
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public returns (bool success) {
        assert(super.transfer(_to, _amount)); // Handle basic transfer functionality
        // @imp 08 Have staking contract receive the token and handle the data
        assert(TokenReceiver(_to).tokensReceived(msg.sender, _amount, _data));
        success = true;
    }

    function _addMinter(address _account) internal {
        _minters[_account] = true;
        emit MinterAdded(_account);
    }

    function _removeMinter(address _account) internal {
        _minters[_account] = false;
        emit MinterRemoved(_account);
    }
}
