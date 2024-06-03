// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

/**
 * @title Interface of the base {DataService} contract as defined by the Graph Horizon specification.
 * @notice This interface provides a guardrail for contracts that use the Data Service framework
 * to implement a data service on Graph Horizon. Much of the specification is intentionally loose
 * to allow for greater flexibility when designing a data service. It's not possible to guarantee that
 * an implementation will honor the Data Service framework guidelines so it's advised to always review
 * the implementation code and the documentation.
 * @dev This interface is expected to be inherited and extended by a data service interface. It can be
 * used to interact with it however it's advised to use the more specific parent interface.
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
     * Verifies provision parameters and rejects registration in the event they are not valid.
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
     * @notice Accepts staged parameters in the provision of a service provider in the {Graph Horizon staking
     * contract}.
     * @dev Provides a way for the data service to validate and accept provision parameter changes. Call {_acceptProvision}.
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
