// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

/**
 * @title Interface of the base {DataService} contract as defined by the Graph Horizon specification.
 * @dev This interface provides a guardrail for data service implementations that utilize Graph Horizon. 
 * It's expected that implementations follow the specification however much of it is intentionally loose 
 * to allow for greater flexibility when designing a data service. For specifics always check the data 
 * service implementation.
 
 * In general, this is a great starting point for data services that want to use Graph Horizon
 * to provide economic security for a service being provided. It assumes two main forms of retribution for
 * service providers:
 * - service payment, to compensate ongoing work required to serve customers requests
 * - service fees, earnt by serving customer requests, ideally leveraging {GraphPayments} to collect fees from the payer
 *
 * TIP: TODO: link to data service framework documentation
 */
interface IDataService {
    /**
     * @notice Emitted when a service provider is registered with the data service.
     * @param serviceProvider The address of the service provider.
     */
    event ServiceProviderRegistered(address indexed serviceProvider);

    /**
     * @notice Emitted when a service provider accepts a provision in {Graph Horizon staking contract}.
     * @param serviceProvider The address of the service provider.
     */
    event ProvisionAccepted(address indexed serviceProvider);

    /**
     * @notice Emitted when a service provider starts providing the service.
     * @param serviceProvider The address of the service provider.
     */
    event ServiceStarted(address indexed serviceProvider);

    /**
     * @notice Emitted when a service provider stops providing the service.
     * @param serviceProvider The address of the service provider.
     */
    event ServiceStopped(address indexed serviceProvider);

    /**
     * @notice Emitted when a service provider collects payment.
     * @param serviceProvider The address of the service provider.
     * @param feeType The type of fee to collect as defined in {GraphPayments}.
     * @param tokens The amount of tokens collected.
     */
    event ServicePaymentCollected(
        address indexed serviceProvider,
        IGraphPayments.PaymentTypes indexed feeType,
        uint256 tokens
    );

    /**
     * @notice Emitted when a service provider is slashed.
     * @param serviceProvider The address of the service provider.
     * @param tokens The amount of tokens slashed.
     */
    event ServiceProviderSlashed(address indexed serviceProvider, uint256 tokens);

    /**
     * @notice Thrown to signal that a feature is not implemented by a data service.
     */
    error DataServiceFeatureNotImplemented();

    /**
     * @notice Registers a service provider with the data service. The service provider can now
     * start providing the service.
     * @dev Before registering, the service provider must have created a provision in the
     * Graph Horizon staking contract with parameters that are compatible with the data service.
     *
     * Verifies the provision parameters and marks it as accepted it in the Graph Horizon
     * staking contract using {_acceptProvision}.
     *
     * Emits a {ServiceProviderRegistered} event.
     *
     * NOTE: Failing to accept the provision will result in the service provider operating
     * on an unverified provision. Depending on of the data service this can be a security
     * risk as the protocol won't be able to guarantee economic security for the consumer.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function register(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Accepts the provision of a service provider in the {Graph Horizon staking
     * contract}.
     * @dev Provides a way for the data service to revalidate and reaccept a provision that
     * had a parameter change. Should call {_acceptProvision}.
     *
     * Emits a {ProvisionAccepted} event.
     *
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function acceptProvision(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Service provider starts providing the service.
     * @dev Emits a {ServiceStarted} event.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function startService(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Service provider stops providing the service.
     * @dev Emits a {ServiceStopped} event.
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function stopService(address serviceProvider, bytes calldata data) external;

    /**
     * @notice Collects payment earnt by the service provider.
     * @dev The implementation of this function is expected to interact with {GraphPayments}
     * to collect payment from the service payer, which is done via {IGraphPayments-collect}.
     * @param serviceProvider The address of the service provider.
     *
     * Emits a {ServicePaymentCollected} event.
     *
     * NOTE: Data services that are vetted by the Graph Council might qualify for a portion of
     * protocol issuance to cover for these payments. In this case, the funds are taken by
     * interacting with the rewards manager contract instead of the {GraphPayments} contract.
     * @param serviceProvider The address of the service provider.
     * @param feeType The type of fee to collect as defined in {GraphPayments}.
     * @param data Custom data, usage defined by the data service.
     */
    function collect(address serviceProvider, IGraphPayments.PaymentTypes feeType, bytes calldata data) external;

    /**
     * @notice Slash a service provider for misbehaviour.
     * @dev To slash the service provider's provision the function should call
     * {Staking-slash}.
     *
     * Emits a {ServiceProviderSlashed} event.
     *
     * @param serviceProvider The address of the service provider.
     * @param data Custom data, usage defined by the data service.
     */
    function slash(address serviceProvider, bytes calldata data) external;
}
