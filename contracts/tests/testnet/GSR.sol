pragma solidity ^0.6.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "../../governance/Governed.sol";
import "../../token/IGraphToken.sol";

/**
 * @title Graph Saving Rate contract
 * @dev This contracts receives GDAI deposits and provides an interests rate for use in testnet.
 */
contract GSRManager is Governed, ERC20, ERC20Burnable {
    using SafeMath for uint256;

    uint256 public ratio;
    uint256 public reserves;
    uint256 public acc;
    uint256 public ts;
    mapping(address => uint256) public balances;
    IGraphToken public token; // GRT

    event Join(address indexed account, uint256 tokens);

    /**
     * @dev Graph Saving Rate constructor.
     */
    constructor() public {
        Governed._initialize(msg.sender);
    }

    function setRatio() external {}

    function tokenBalance(address _account) external returns (uint256) {}

    function join(address _account, uint256 _tokens) external {}

    function exit() external {}

    function drip() external returns (uint256) {}
}
