// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { GraphBaseTest } from "../GraphBase.t.sol";
import { GraphDirectory } from "./../../contracts/utilities/GraphDirectory.sol";
import { GraphDirectoryImplementation } from "./GraphDirectoryImplementation.sol";

contract GraphDirectoryTest is GraphBaseTest {
    function test_WhenTheContractIsDeployedWithAValidController() external {
        vm.expectEmit();
        emit GraphDirectory.GraphDirectoryInitialized(
            _getContractFromController("GraphToken"),
            _getContractFromController("Staking"),
            _getContractFromController("GraphPayments"),
            _getContractFromController("PaymentsEscrow"),
            address(controller),
            _getContractFromController("EpochManager"),
            _getContractFromController("RewardsManager"),
            _getContractFromController("GraphTokenGateway"),
            _getContractFromController("GraphProxyAdmin"),
            _getContractFromController("Curation")
        );
        _deployImplementation(address(controller));
    }

    function test_RevertWhen_TheContractIsDeployedWithAnInvalidController(address controller_) external {
        vm.assume(controller_ != address(controller));
        vm.assume(controller_ != address(0));

        vm.expectRevert(); // call to getContractProxy on a random address reverts
        _deployImplementation(controller_);
    }

    function test_RevertWhen_TheContractIsDeployedWithTheZeroAddressAsTheInvalidController() external {
        vm.expectRevert(abi.encodeWithSelector(GraphDirectory.GraphDirectoryInvalidZeroAddress.selector, "Controller")); // call to getContractProxy on a random address reverts
        _deployImplementation(address(0));
    }

    function test_WhenTheContractGettersAreCalled() external {
        GraphDirectoryImplementation directory = _deployImplementation(address(controller));

        assertEq(_getContractFromController("GraphToken"), address(directory.graphToken()));
        assertEq(_getContractFromController("Staking"), address(directory.graphStaking()));
        assertEq(_getContractFromController("GraphPayments"), address(directory.graphPayments()));
        assertEq(_getContractFromController("PaymentsEscrow"), address(directory.graphPaymentsEscrow()));
        assertEq(_getContractFromController("EpochManager"), address(directory.graphEpochManager()));
        assertEq(_getContractFromController("RewardsManager"), address(directory.graphRewardsManager()));
        assertEq(_getContractFromController("GraphTokenGateway"), address(directory.graphTokenGateway()));
        assertEq(_getContractFromController("GraphProxyAdmin"), address(directory.graphProxyAdmin()));
        assertEq(_getContractFromController("Curation"), address(directory.graphCuration()));
    }

    function test_RevertWhen_AnInvalidContractGetterIsCalled() external {
        // Zero out the Staking contract address to simulate a non registered contract
        bytes32 storageSlot = keccak256(abi.encode(keccak256("Staking"), 5));
        vm.store(address(controller), storageSlot, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(GraphDirectory.GraphDirectoryInvalidZeroAddress.selector, "Staking"));
        _deployImplementation(address(controller));
    }

    function _deployImplementation(address _controller) private returns (GraphDirectoryImplementation) {
        return new GraphDirectoryImplementation(_controller);
    }

    function _getContractFromController(bytes memory _contractName) private view returns (address) {
        return controller.getContractProxy(keccak256(_contractName));
    }
}
