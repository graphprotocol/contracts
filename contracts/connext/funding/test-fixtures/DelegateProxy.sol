pragma solidity 0.5.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DelegateProxy {
    function () external payable { }

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
            ERC20(assetId).transfer(recipient, amount);
        }
    }
}
