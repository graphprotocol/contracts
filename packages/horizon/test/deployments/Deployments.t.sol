// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../GraphBase.t.sol";

contract GraphDeploymentsTest is GraphBaseTest {

    /*
     * HELPERS
     */

    function _getContractFromController(bytes memory _contractName) private view returns (address) {
        return controller.getContractProxy(keccak256(_contractName));
    }

    /*
     * TESTS
     */

    function testDeployments() public view {
        assertEq(_getContractFromController("GraphPayments"), address(payments));
        assertEq(_getContractFromController("GraphToken"), address(token));
        assertEq(_getContractFromController("Staking"), address(staking));
        assertEq(_getContractFromController("PaymentsEscrow"), address(escrow));
        assertEq(_getContractFromController("GraphProxyAdmin"), address(proxyAdmin));
    }
}
