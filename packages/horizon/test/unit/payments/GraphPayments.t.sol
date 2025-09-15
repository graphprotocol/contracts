// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { GraphPayments } from "../../../contracts/payments/GraphPayments.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract GraphPaymentsExtended is GraphPayments {
    constructor(address controller, uint256 protocolPaymentCut) GraphPayments(controller, protocolPaymentCut) {}

    function readController() external view returns (address) {
        return address(_graphController());
    }
}

contract GraphPaymentsTest is HorizonStakingSharedTest {
    using PPMMath for uint256;

    struct CollectPaymentData {
        uint256 escrowBalance;
        uint256 paymentsBalance;
        uint256 receiverBalance;
        uint256 receiverDestinationBalance;
        uint256 delegationPoolBalance;
        uint256 dataServiceBalance;
        uint256 receiverStake;
    }

    struct CollectTokensData {
        uint256 tokensProtocol;
        uint256 tokensDataService;
        uint256 tokensDelegation;
        uint256 receiverExpectedPayment;
    }

    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _dataServiceCut,
        address _paymentsDestination
    ) private {
        // Previous balances
        CollectPaymentData memory previousBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            receiverDestinationBalance: token.balanceOf(_paymentsDestination),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService),
            receiverStake: staking.getStake(_receiver)
        });

        // Calculate cuts
        CollectTokensData memory collectTokensData = CollectTokensData({
            tokensProtocol: 0,
            tokensDataService: 0,
            tokensDelegation: 0,
            receiverExpectedPayment: 0
        });
        collectTokensData.tokensProtocol = _tokens.mulPPMRoundUp(payments.PROTOCOL_PAYMENT_CUT());
        collectTokensData.tokensDataService = (_tokens - collectTokensData.tokensProtocol).mulPPMRoundUp(
            _dataServiceCut
        );

        {
            IHorizonStakingTypes.DelegationPool memory pool = staking.getDelegationPool(_receiver, _dataService);
            if (pool.shares > 0) {
                collectTokensData.tokensDelegation = (_tokens -
                    collectTokensData.tokensProtocol -
                    collectTokensData.tokensDataService).mulPPMRoundUp(
                        staking.getDelegationFeeCut(_receiver, _dataService, _paymentType)
                    );
            }
        }

        collectTokensData.receiverExpectedPayment =
            _tokens -
            collectTokensData.tokensProtocol -
            collectTokensData.tokensDataService -
            collectTokensData.tokensDelegation;

        (, address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(payments));
        emit IGraphPayments.GraphPaymentCollected(
            _paymentType,
            msgSender,
            _receiver,
            _dataService,
            _tokens,
            collectTokensData.tokensProtocol,
            collectTokensData.tokensDataService,
            collectTokensData.tokensDelegation,
            collectTokensData.receiverExpectedPayment,
            _paymentsDestination
        );
        payments.collect(_paymentType, _receiver, _tokens, _dataService, _dataServiceCut, _paymentsDestination);

        // After balances
        CollectPaymentData memory afterBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            receiverDestinationBalance: token.balanceOf(_paymentsDestination),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService),
            receiverStake: staking.getStake(_receiver)
        });

        // Check receiver balance after payment
        assertEq(
            afterBalances.receiverBalance - previousBalances.receiverBalance,
            _paymentsDestination == _receiver ? collectTokensData.receiverExpectedPayment : 0
        );
        assertEq(token.balanceOf(address(payments)), 0);

        // Check receiver destination balance after payment
        assertEq(
            afterBalances.receiverDestinationBalance - previousBalances.receiverDestinationBalance,
            _paymentsDestination == address(0) ? 0 : collectTokensData.receiverExpectedPayment
        );

        // Check receiver stake after payment
        assertEq(
            afterBalances.receiverStake - previousBalances.receiverStake,
            _paymentsDestination == address(0) ? collectTokensData.receiverExpectedPayment : 0
        );

        // Check delegation pool balance after payment
        assertEq(
            afterBalances.delegationPoolBalance - previousBalances.delegationPoolBalance,
            collectTokensData.tokensDelegation
        );

        // Check that the escrow account has been updated
        assertEq(previousBalances.escrowBalance, afterBalances.escrowBalance + _tokens);

        // Check that payments balance didn't change
        assertEq(previousBalances.paymentsBalance, afterBalances.paymentsBalance);

        // Check data service balance after payment
        assertEq(
            afterBalances.dataServiceBalance - previousBalances.dataServiceBalance,
            collectTokensData.tokensDataService
        );
    }

    /*
     * TESTS
     */

    function testConstructor() public {
        uint256 protocolCut = 100_000;
        GraphPaymentsExtended newPayments = new GraphPaymentsExtended(address(controller), protocolCut);
        assertEq(address(newPayments.readController()), address(controller));
        assertEq(newPayments.PROTOCOL_PAYMENT_CUT(), protocolCut);
    }

    function testConstructor_RevertIf_InvalidProtocolPaymentCut(uint256 protocolPaymentCut) public {
        protocolPaymentCut = bound(protocolPaymentCut, MAX_PPM + 1, type(uint256).max);

        resetPrank(users.deployer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphPayments.GraphPaymentsInvalidCut.selector,
            protocolPaymentCut
        );
        vm.expectRevert(expectedError);
        new GraphPayments(address(controller), protocolPaymentCut);
    }

    function testInitialize() public {
        // Deploy new instance to test initialization
        GraphPayments newPayments = new GraphPayments(address(controller), 100_000);

        // Should revert if not called by onlyInitializer
        vm.expectRevert();
        newPayments.initialize();
    }

    function testCollect(
        uint256 amount,
        uint256 amountToCollect,
        uint256 dataServiceCut,
        uint256 tokensDelegate,
        uint256 delegationFeeCut
    ) public useIndexer useProvision(amount, 0, 0) {
        amountToCollect = bound(amountToCollect, 1, MAX_STAKING_TOKENS);
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        tokensDelegate = bound(tokensDelegate, 1, MAX_STAKING_TOKENS);
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM); // Covers zero, max, and everything in between

        // Set delegation fee cut
        _setDelegationFeeCut(
            users.indexer,
            subgraphDataServiceAddress,
            IGraphPayments.PaymentTypes.QueryFee,
            delegationFeeCut
        );

        // Delegate tokens
        tokensDelegate = bound(tokensDelegate, MIN_DELEGATION, MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, tokensDelegate, 0);

        // Add tokens in escrow
        address escrowAddress = address(escrow);
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        _collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut,
            users.indexer
        );
        vm.stopPrank();
    }

    function testCollect_WithRestaking(
        uint256 amount,
        uint256 amountToCollect,
        uint256 dataServiceCut,
        uint256 tokensDelegate,
        uint256 delegationFeeCut
    ) public useIndexer useProvision(amount, 0, 0) {
        amountToCollect = bound(amountToCollect, 1, MAX_STAKING_TOKENS);
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        tokensDelegate = bound(tokensDelegate, 1, MAX_STAKING_TOKENS);
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM); // Covers zero, max, and everything in between

        // Set delegation fee cut
        _setDelegationFeeCut(
            users.indexer,
            subgraphDataServiceAddress,
            IGraphPayments.PaymentTypes.QueryFee,
            delegationFeeCut
        );

        // Delegate tokens
        tokensDelegate = bound(tokensDelegate, MIN_DELEGATION, MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, tokensDelegate, 0);

        // Add tokens in escrow
        address escrowAddress = address(escrow);
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        _collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut,
            address(0)
        );
        vm.stopPrank();
    }

    function testCollect_WithBeneficiary(
        uint256 amount,
        uint256 amountToCollect,
        uint256 dataServiceCut,
        uint256 tokensDelegate,
        uint256 delegationFeeCut
    ) public useIndexer useProvision(amount, 0, 0) {
        amountToCollect = bound(amountToCollect, 1, MAX_STAKING_TOKENS);
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        tokensDelegate = bound(tokensDelegate, 1, MAX_STAKING_TOKENS);
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM); // Covers zero, max, and everything in between

        // Set delegation fee cut
        _setDelegationFeeCut(
            users.indexer,
            subgraphDataServiceAddress,
            IGraphPayments.PaymentTypes.QueryFee,
            delegationFeeCut
        );

        // Delegate tokens
        tokensDelegate = bound(tokensDelegate, MIN_DELEGATION, MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, tokensDelegate, 0);

        // Add tokens in escrow
        address escrowAddress = address(escrow);
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        _collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut,
            vm.addr(1) // use some random address as beneficiary
        );
        vm.stopPrank();
    }

    function testCollect_NoProvision(
        uint256 amount,
        uint256 dataServiceCut,
        uint256 delegationFeeCut
    ) public useIndexer {
        amount = bound(amount, 1, MAX_STAKING_TOKENS);
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM); // Covers zero, max, and everything in between

        // Set delegation fee cut
        _setDelegationFeeCut(
            users.indexer,
            subgraphDataServiceAddress,
            IGraphPayments.PaymentTypes.QueryFee,
            delegationFeeCut
        );

        // Add tokens in escrow
        address escrowAddress = address(escrow);
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        // Collect payments through GraphPayments
        vm.startPrank(escrowAddress);
        _collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut,
            users.indexer
        );
        vm.stopPrank();
    }

    function testCollect_RevertWhen_InvalidDataServiceCut(
        uint256 amount,
        uint256 dataServiceCut
    )
        public
        useIndexer
        useProvision(amount, 0, 0)
        useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut)
    {
        dataServiceCut = bound(dataServiceCut, MAX_PPM + 1, type(uint256).max);

        resetPrank(users.deployer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphPayments.GraphPaymentsInvalidCut.selector,
            dataServiceCut
        );
        vm.expectRevert(expectedError);
        payments.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut,
            users.indexer
        );
    }

    function testCollect_WithZeroAmount(uint256 amount) public useIndexer useProvision(amount, 0, 0) {
        _collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, 0, subgraphDataServiceAddress, 0, users.indexer);
    }

    function testCollect_RevertWhen_UnauthorizedCaller(uint256 amount) public useIndexer useProvision(amount, 0, 0) {
        vm.assume(amount > 0 && amount <= MAX_STAKING_TOKENS);

        // Try to collect without being the escrow
        resetPrank(users.indexer);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(payments), 0, amount)
        );

        payments.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );
    }

    function testCollect_WithNoDelegation(
        uint256 amount,
        uint256 dataServiceCut,
        uint256 delegationFeeCut
    ) public useIndexer useProvision(amount, 0, 0) {
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM);

        // Set delegation fee cut
        _setDelegationFeeCut(
            users.indexer,
            subgraphDataServiceAddress,
            IGraphPayments.PaymentTypes.QueryFee,
            delegationFeeCut
        );

        // Add tokens in escrow
        address escrowAddress = address(escrow);
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        _collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut,
            users.indexer
        );
        vm.stopPrank();
    }

    function testCollect_ViaMulticall(uint256 amount) public useIndexer {
        amount = bound(amount, 1, MAX_STAKING_TOKENS / 2); // Divide by 2 as we'll make two calls

        address escrowAddress = address(escrow);
        mint(escrowAddress, amount * 2);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount * 2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            payments.collect.selector,
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            100_000, // 10%
            users.indexer
        );
        data[1] = abi.encodeWithSelector(
            payments.collect.selector,
            IGraphPayments.PaymentTypes.IndexingFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            200_000, // 20%
            users.indexer
        );

        payments.multicall(data);
    }
}
