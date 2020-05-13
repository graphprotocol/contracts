pragma solidity 0.6.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DelegateProxy {
    receive() external payable { }

    mapping(address => uint256) public totalAmountWithdrawn;
    address constant CONVENTION_FOR_ETH_TOKEN_ADDRESS = address(0x0);

    function delegate(address to, bytes memory data) public {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, ) = to.delegatecall(data);
        require(success, "Delegate call failed.");
    }

    function withdraw(address assetId, address payable recipient, uint256 amount) public {
        totalAmountWithdrawn[assetId] += amount;
        if (assetId == CONVENTION_FOR_ETH_TOKEN_ADDRESS) {
            recipient.send(amount);
        } else {
            IERC20(assetId).transfer(recipient, amount);
        }
    }
}
