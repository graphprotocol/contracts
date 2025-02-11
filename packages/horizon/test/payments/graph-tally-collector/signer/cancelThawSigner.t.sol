// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphTallyCollector } from "../../../../contracts/interfaces/IGraphTallyCollector.sol";

import { GraphTallyTest } from "../GraphTallyCollector.t.sol";

contract GraphTallyCancelThawSignerTest is GraphTallyTest {

    /*
     * TESTS
     */

    function testGraphTally_CancelThawSigner() public useGateway useSigner {
        _thawSigner(signer);
        _cancelThawSigner(signer);
    }

    function testGraphTally_CancelThawSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }
    
    function testGraphTally_CancelThawSigner_RevertWhen_NotThawing() public useGateway useSigner {
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphTallyCollector.GraphTallyCollectorSignerNotThawing.selector,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.cancelThawSigner(signer);
    }
}
