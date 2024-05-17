// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { HorizonStaking } from "../contracts/HorizonStaking.sol";
import { ControllerMock } from "../contracts/mocks/ControllerMock.sol";
import { HorizonStakingExtension } from "../contracts/HorizonStakingExtension.sol";
import { ExponentialRebates } from "../contracts/utils/ExponentialRebates.sol";
import { IHorizonStaking } from "../contracts/IHorizonStaking.sol";
import { IHorizonStakingTypes } from "../contracts/IHorizonStakingTypes.sol";
import { GRTTokenMock } from "../contracts/mocks/GRTTokenMock.sol";

contract HorizonStakingTest is Test, IHorizonStakingTypes {
    ExponentialRebates rebates;
    HorizonStakingExtension ext;
    IHorizonStaking staking;
    ControllerMock controller;
    GRTTokenMock token;

    address governor;
    address serviceProvider;
    address operator;
    address dataService;
    address delegator;

    uint32 maxVerifierCut;
    uint32 maxThawingPeriod;

    function setUp() public {
        governor = address(0x1);
        serviceProvider = address(this);
        operator = address(0x1337);
        dataService = address(0x2112);
        delegator = address(0x1982);
        maxVerifierCut = 500000; // 50%
        maxThawingPeriod = 300;

        console.log("Deploying Controller mock");
        controller = new ControllerMock(address(0x1));

        console.log("Deploying GRTToken Mock");
        token = new GRTTokenMock();
        controller.setContractProxy(keccak256("GraphToken"), address(token));

        console.log("Deploying HorizonStaking");
        vm.startPrank(governor);
        rebates = new ExponentialRebates();
        ext = new HorizonStakingExtension(address(controller), address(0x1), address(rebates));
        staking = IHorizonStaking(address(new HorizonStaking(address(controller), address(ext), address(0x1))));
        staking.setMaxThawingPeriod(maxThawingPeriod);
        vm.stopPrank();
    }

    function testOperator_SetOperator() public {
        staking.setOperator(operator, dataService, true);
        assertTrue(staking.isAuthorized(operator, serviceProvider, dataService));
    }

    function testStake_DepositOnCallerStake() public {
        uint256 amount = 1000 ether;
        token.mint(serviceProvider, amount);
        vm.startPrank(serviceProvider);
        token.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();
        assertTrue(staking.getStake(address(serviceProvider)) == amount);
    }

    function testStake_DespoitStakeOnServiceProvider() public {
        uint256 amount = 1000 ether;
        token.mint(operator, amount);
        vm.startPrank(operator);
        token.approve(address(staking), amount);
        staking.stakeTo(serviceProvider, amount);
        vm.stopPrank();
        assertTrue(staking.getStake(address(serviceProvider)) == amount);
    }

    function testProvision_Create() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, dataService);
        assertEq(provisionTokens, amount);
    }

    function testProvision_RevertWhen_ThereIsNoIdleStake() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInsufficientCapacity()");
        vm.expectRevert(expectedError);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);
    }

    function testProvision_OperatorAddTokensToProvision() public {
        uint256 amount = 2000 ether;
        uint256 provisionAmount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, provisionAmount, maxVerifierCut, maxThawingPeriod);

        // Set operator
        staking.setOperator(operator, dataService, true);

        // Add more tokens to the provision
        vm.startPrank(operator);
        staking.addToProvision(serviceProvider, dataService, 500 ether);
        vm.stopPrank();

        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, dataService);
        assertEq(provisionTokens, 1500 ether);
    }

    function testProvision_RevertWhen_OperatorNotAuthorized() public {
        uint256 amount = 1000 ether;

        vm.startPrank(operator);
        token.mint(operator, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)", 
            operator,
            serviceProvider,
            dataService
        );
        vm.expectRevert(expectedError);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);
        vm.stopPrank();
    }

    function testThaw_Start() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(serviceProvider, dataService, uint256(0))
        );
        bytes32 thawRequestId = staking.thaw(serviceProvider, dataService, thawAmount);
        assertEq(thawRequestId, expectedThawRequestId);

        // TODO: Need a getThawingTokens function?
    }

    function testThaw_StartASecondThawRequest() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(serviceProvider, dataService, uint256(0))
        );
        bytes32 thawRequestId = staking.thaw(serviceProvider, dataService, thawAmount);
        assertEq(thawRequestId, expectedThawRequestId);

        uint256 thawAmount2 = 100 ether;
        bytes32 expectedThawRequestId2 = keccak256(
            abi.encodePacked(serviceProvider, dataService, uint256(1))
        );
        bytes32 thawRequestId2 = staking.thaw(serviceProvider, dataService, thawAmount2);
        assertEq(thawRequestId2, expectedThawRequestId2);

        // TODO: Need a getThawingTokens function?
    }

    function testThaw_OperatorCanStartThawing() public {
        uint256 amount = 1000 ether;

        staking.setOperator(operator, dataService, true);

        vm.startPrank(operator);
        token.mint(operator, amount);
        token.approve(address(staking), amount);
        staking.stakeTo(serviceProvider, amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);
        vm.stopPrank();

        uint256 thawAmount = 500 ether;
        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(serviceProvider, dataService, uint256(0))
        );
        bytes32 thawRequestId = staking.thaw(serviceProvider, dataService, thawAmount);
        assertEq(thawRequestId, expectedThawRequestId);
    }

    function testThaw_RevertWhen_OperatorNotAuthorized() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        vm.prank(operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)", 
            operator,
            serviceProvider,
            dataService
        );
        vm.expectRevert(expectedError);
        staking.thaw(serviceProvider, dataService, thawAmount);
    }

    function testThaw_RevertWhen_InsufficientTokensAvailable() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 1500 ether;
        vm.expectRevert("insufficient tokens available");
        staking.thaw(serviceProvider, dataService, thawAmount);
    }

    function testThaw_RevertWhen_OverMaxThawRequests() public {
        uint256 amount = 2000 ether;
        uint256 thawAmount = 10 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        for (uint256 i = 0; i < 100; i++) {
            staking.thaw(serviceProvider, dataService, thawAmount);
        }

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingTooManyThawRequests()");
        vm.expectRevert(expectedError);
        staking.thaw(serviceProvider, dataService, thawAmount);
    }

    function testThaw_RevertWhen_ThawingZeroTokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 0 ether;
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.thaw(serviceProvider, dataService, thawAmount);
    }

    function testDeprovision_Tokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        staking.deprovision(serviceProvider, dataService, thawAmount);
        uint256 idleStake = staking.getIdleStake(serviceProvider);
        assertEq(idleStake, 500 ether);
    }

    function testDeprovision_OperatorMovingTokens() public {
        uint256 amount = 1000 ether;

        staking.setOperator(operator, dataService, true);

        vm.startPrank(operator);
        token.mint(operator, amount);
        token.approve(address(staking), amount);
        staking.stakeTo(serviceProvider, amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        staking.deprovision(serviceProvider, dataService, thawAmount);
        vm.stopPrank();
        uint256 idleStake = staking.getIdleStake(serviceProvider);
        assertEq(idleStake, 500 ether);
    }

    function testDeprovision_RevertWhen_OperatorNotAuthorized() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        vm.prank(operator);
        vm.expectRevert("!auth");
        staking.deprovision(serviceProvider, dataService, thawAmount);
    }

    function testDeprovision_RevertWhen_ZeroTokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.deprovision(serviceProvider, dataService, 0);
    }

    function testDeprovision_RevertWhen_NoThawingTokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNotEnoughThawedTokens()");
        vm.expectRevert(expectedError);
        staking.deprovision(serviceProvider, dataService, amount);
    }

    function testDeprovision_RevertWhen_StillThawing() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingStillThawing(uint256,uint256)",
            block.timestamp,
            block.timestamp + maxThawingPeriod
        );
        vm.expectRevert(expectedError);
        staking.deprovision(serviceProvider, dataService, thawAmount);
    }

    function testDeprovision_RevertWhen_NotEnoughThawedTokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNotEnoughThawedTokens()");
        vm.expectRevert(expectedError);
        staking.deprovision(serviceProvider, dataService, thawAmount + 1);
    }

    function testReprovision_MovingTokens() public {
        address newDataService = address(0x2113);
        uint256 amount = 2000 ether;
        uint256 provisionAmount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, provisionAmount, maxVerifierCut, maxThawingPeriod);
        staking.provision(serviceProvider, newDataService, provisionAmount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        staking.reprovision(serviceProvider, dataService, newDataService, thawAmount);
        uint256 idleStake = staking.getIdleStake(serviceProvider);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, newDataService);
        assertEq(provisionTokens, 1500 ether);
    }

    function testReprovision_OperatorMovingTokens() public {
        address newDataService = address(0x2113);
        uint256 amount = 2000 ether;
        uint256 provisionAmount = 1000 ether;

        // Set operator for both data services
        staking.setOperator(operator, dataService, true);
        staking.setOperator(operator, newDataService, true);

        vm.startPrank(operator);
        token.mint(operator, amount);
        token.approve(address(staking), amount);
        staking.stakeTo(serviceProvider, amount);
        staking.provision(serviceProvider, dataService, provisionAmount, maxVerifierCut, maxThawingPeriod);
        staking.provision(serviceProvider, newDataService, provisionAmount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        staking.reprovision(serviceProvider, dataService, newDataService, thawAmount);
        vm.stopPrank();

        uint256 idleStake = staking.getIdleStake(serviceProvider);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, newDataService);
        assertEq(provisionTokens, 1500 ether);
    }

    function testReprovision_RevertWhen_OperatorNotAuthorized() public {
        address newDataService = address(0x2113);
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        vm.prank(operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            operator,
            serviceProvider,
            dataService
        );
        vm.expectRevert(expectedError);
        staking.reprovision(serviceProvider, dataService, newDataService, thawAmount);
    }

    function testReprovision_RevertWhen_OperatorNotAuthorizedForNewDataService() public {
        address newDataService = address(0x2113);
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        // Set operator for the old data service only
        staking.setOperator(operator, dataService, true);

        vm.prank(operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            operator,
            serviceProvider,
            newDataService
        );
        vm.expectRevert(expectedError);
        staking.reprovision(serviceProvider, dataService, newDataService, thawAmount);
    }

    function testReprovision_RevertWhen_NoThawingTokens() public {
        address newDataService = address(0x2113);
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNotEnoughThawedTokens()");
        vm.expectRevert(expectedError);
        staking.reprovision(serviceProvider, dataService, newDataService, amount);
    }

    function testReprovision_RevertWhen_StillThawing() public {
        address newDataService = address(0x2113);
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingStillThawing(uint256,uint256)",
            block.timestamp,
            block.timestamp + maxThawingPeriod
        );
        vm.expectRevert(expectedError);
        staking.reprovision(serviceProvider, dataService, newDataService, thawAmount);
    }

    function testReprovision_RevertWhen_NotEnoughThawedTokens() public {
        address newDataService = address(0x2113);
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNotEnoughThawedTokens()");
        vm.expectRevert(expectedError);
        staking.reprovision(serviceProvider, dataService, newDataService, thawAmount + 1);
    }

    function testUnstake_Tokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        staking.deprovision(serviceProvider, dataService, thawAmount);
        staking.unstake(thawAmount);
        uint256 idleStake = staking.getIdleStake(serviceProvider);
        assertEq(idleStake, 0 ether);

        uint256 provisionTokens = token.balanceOf(address(serviceProvider));
        assertEq(provisionTokens, thawAmount);
    }

    function testUnstake_RevertWhen_ZeroTokens() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        staking.deprovision(serviceProvider, dataService, thawAmount);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.unstake(0);
    }

    function testUnstake_RevertWhen_NoIdleStake() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInsufficientCapacity()");
        vm.expectRevert(expectedError);
        staking.unstake(amount);
    }

    function testUnstake_RevertWhen_NotDeprovision() public {
        uint256 amount = 1000 ether;

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        uint256 thawAmount = 500 ether;
        staking.thaw(serviceProvider, dataService, thawAmount);

        skip(maxThawingPeriod + 1);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInsufficientCapacity()");
        vm.expectRevert(expectedError);
        staking.unstake(thawAmount);
    }

    function testSlash_Tokens() public {
        uint256 amount = 1000 ether;
        uint256 slashAmount = 500 ether;
        uint256 verifierCutAmount = 100 ether;
        address verifierCutDestination = address(0x2114);

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.prank(dataService);
        staking.slash(serviceProvider, slashAmount, verifierCutAmount, verifierCutDestination);
        
        uint256 provisionTokens = staking.getProviderTokensAvailable(serviceProvider, dataService);
        assertEq(provisionTokens, 500 ether);

        uint256 verifierTokens = token.balanceOf(address(verifierCutDestination));
        assertEq(verifierTokens, verifierCutAmount);
    }

    function testSlash_DelegationDisabled_SlashingOverProvisionTokens() public {
        // Disable delegation slashing
        vm.prank(governor);
        staking.setDelegationSlashingEnabled(false);
        
        uint256 amount = 1000 ether;
        uint256 slashAmount = 1500 ether;
        uint256 verifierCutAmount = 500 ether;
        uint256 delegationAmount = 500 ether;
        address verifierCutDestination = address(0x2114);
        uint32 delegationRatio = 5;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);
        vm.stopPrank();

        uint256 totalTokensWithDelegation = staking.getTokensAvailable(serviceProvider, dataService, delegationRatio);
        assertEq(totalTokensWithDelegation, 1500 ether);

        vm.prank(dataService);
        staking.slash(serviceProvider, slashAmount, verifierCutAmount, verifierCutDestination);
        
        uint256 provisionProviderTokens = staking.getProviderTokensAvailable(serviceProvider, dataService);
        assertEq(provisionProviderTokens, 0 ether);

        uint256 verifierTokens = token.balanceOf(address(verifierCutDestination));
        assertEq(verifierTokens, verifierCutAmount);
    }

    function testSlash_RevertWhen_NoProvision() public {
        uint256 amount = 1000 ether;
        uint256 slashAmount = 1500 ether;
        uint256 verifierCutAmount = 100 ether;
        address verifierCutDestination = address(0x2114);

        token.mint(serviceProvider, amount);
        token.approve(address(staking), amount);
        staking.stake(amount);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            slashAmount, 0 ether
        );
        vm.expectRevert(expectedError);
        vm.prank(dataService);
        staking.slash(serviceProvider, slashAmount, verifierCutAmount, verifierCutDestination);
    }

    function testDelegation_Tokens() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);
        vm.stopPrank();

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(serviceProvider, dataService);
        assertEq(delegatedTokens, delegationAmount);
    }

    function testUndelegate_Tokens() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);

        Delegation memory delegation = staking.getDelegation(delegator, serviceProvider, dataService);
        staking.undelegate(serviceProvider, dataService, delegation.shares);
        vm.stopPrank();

        Delegation memory thawingDelegation = staking.getDelegation(delegator, serviceProvider, dataService);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingDelegation.lastThawRequestId);

        assertEq(thawRequest.shares, delegation.shares);
    }

    function testUndelegate_RevertWhen_ZeroTokens() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);
        vm.stopPrank();

        vm.expectRevert("!shares");
        staking.undelegate(serviceProvider, dataService, 0);
    }

    function testUndelegate_RevertWhen_OverUndelegation() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);
        vm.stopPrank();

        vm.expectRevert("!shares-avail");
        staking.undelegate(serviceProvider, dataService, delegationAmount + 1);
    }

    function testWithdrawDelegation_Tokens() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);

        Delegation memory delegation = staking.getDelegation(delegator, serviceProvider, dataService);
        staking.undelegate(serviceProvider, dataService, delegation.shares);

        Delegation memory thawingDelegation = staking.getDelegation(delegator, serviceProvider, dataService);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingDelegation.lastThawRequestId);
        
        skip(thawRequest.thawingUntil + 1);

        staking.withdrawDelegated(serviceProvider, dataService, address(0x0), 0);
        vm.stopPrank();
        
        uint256 delegatorTokens = token.balanceOf(address(delegator));
        assertEq(delegatorTokens, delegationAmount);
    }

    function testWithdrawDelegation_RevertWhen_NotThawing() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNoThawRequest()");
        vm.expectRevert(expectedError);
        staking.withdrawDelegated(serviceProvider, dataService, address(0x0), 0);
        vm.stopPrank();
    }

    function testWithdrawDelegation_RevertWhen_StillThawing() public {
        uint256 amount = 1000 ether;
        uint256 delegationAmount = 500 ether;

        token.mint(serviceProvider, amount);
        token.mint(delegator, delegationAmount);
        token.approve(address(staking), amount);
        staking.stake(amount);
        staking.provision(serviceProvider, dataService, amount, maxVerifierCut, maxThawingPeriod);

        vm.startPrank(delegator);
        token.approve(address(staking), delegationAmount);
        staking.delegate(serviceProvider, dataService, delegationAmount, 0);

        Delegation memory delegation = staking.getDelegation(delegator, serviceProvider, dataService);
        staking.undelegate(serviceProvider, dataService, delegation.shares);

        Delegation memory thawingDelegation = staking.getDelegation(delegator, serviceProvider, dataService);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingDelegation.lastThawRequestId);

        staking.withdrawDelegated(serviceProvider, dataService, address(0x0), 0);
        vm.stopPrank();
    }
}
