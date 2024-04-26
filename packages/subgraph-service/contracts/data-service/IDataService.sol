// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

/**
 * @title Interface of the base {DataService} contract as defined by the Graph Horizon specification.
 * @dev This interface provides a guardrail for data service implementations that utilize
 * Graph Horizon. Much of the specification is loose to allow for greater flexibility when
 * designing a data service.
 *
 * In general, this is a great starting point for data services that want to use Graph Horizon
 * to provide economic security for a service being provided, with two main forms of retribution for
 * service providers:
 * - service payment, for ongoing work required to serve customers requests
 * - fees, for serving customer requests, ideally leveraging Graph Payments to collect fees from the payer
 *
 * TIP: TODO: link to data service framework documentation
 */
interface IDataService {
    /**
     * @notice Thrown to signal that a feature is not implemented by a data service.
     */
    error DataServiceFeatureNotImplemented();

    /**
     * @notice Registers a service provider with the data service. The service provider can now
     * start providing the service.
     * @dev Before calling the function, the service provider must have created a provision
     * in the Graph Horizon staking contract with parameters that are compatible with the
     * data service.
     *
     * The implementation of this function is expected to verify the provision parameters
     * and mark it as accepted it in the Graph Horizon staking contract using {_acceptProvision}.
     *
     * NOTE: Failing to accept the provision will result in the service provider operating
     * on an unverified provision. Depending on of the data service this can be a security
     * risk as the protocol won't be able to guarantee economic security for the consumer.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function register(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Accepts the provision of a service provider in the Graph Horizon staking
     * contract.
     * @dev Provides a way for the data service to revalidate and reaccept a provision that
     * had a parameter change. Should call {_acceptProvision}.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function acceptProvision(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Service provider starts providing the service.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function startService(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Service provider collects payment for the service being provided.
     * @dev This is payment owed to a service provided for ongoing work required to fullfil
     * customer requests. How the funds to fullfill the payment are procured is up to the data service.
     *
     * NOTE: Data services that are vetted by the Graph Council might qualify for a portion of
     * the protocol issuance to cover these payments. In this case, the funds are taken by
     * interacting with the rewards manager contract.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function collectServicePayment(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Service provider stops providing the service.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function stopService(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Redeeems fees earnt by the service provider.
     * @dev The implementation of this function is expected to interact with Graph Payments
     * to collect fees from the service payer, which is done via {IGraphPayments-collect}.
     * @param serviceProvider The address of the service provider.
     * @param feeType The type of fee to redeem.
     * @param data Custom data, usage defined by the data service.
     */
    function redeem(
        address serviceProvider,
        IGraphPayments.PaymentTypes feeType,
        bytes calldata data
    ) external returns (uint256 fees);

    /**
     * @notice Slash a service provider for misbehaviour.
     * @dev To slash the service provider's provision the function should call
     * {Staking-slash}.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function slash(address serviceProvider, bytes calldata data) external;
}
