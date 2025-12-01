// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IssuanceStateVerifier
 * @notice Helper contract for verifying issuance state in tests
 */
contract IssuanceStateVerifier {
    error ValueMismatch();
    error MinterRoleNotGranted();

    /**
     * @notice Assert that RewardsManager has the expected RewardsEligibilityOracle set
     */
    function assertRewardsEligibilityOracleSet(
        address rewardsManager,
        address expectedOracle
    ) external view {
        // Read the rewardsEligibilityOracle from the RewardsManager
        (bool success, bytes memory data) = rewardsManager.staticcall(
            abi.encodeWithSignature("rewardsEligibilityOracle()")
        );
        require(success, "Failed to read rewardsEligibilityOracle");
        address actualOracle = abi.decode(data, (address));
        if (actualOracle != expectedOracle) {
            revert ValueMismatch();
        }
    }

    /**
     * @notice Assert that RewardsManager has the expected IssuanceAllocator set
     */
    function assertIssuanceAllocatorSet(
        address rewardsManager,
        address expectedAllocator
    ) external view {
        (bool success, bytes memory data) = rewardsManager.staticcall(
            abi.encodeWithSignature("issuanceAllocator()")
        );
        require(success, "Failed to read issuanceAllocator");
        address actualAllocator = abi.decode(data, (address));
        if (actualAllocator != expectedAllocator) {
            revert ValueMismatch();
        }
    }

    /**
     * @notice Assert that an address has the minter role on a GraphToken
     */
    function assertMinterRole(address graphToken, address account) external view {
        (bool success, bytes memory data) = graphToken.staticcall(
            abi.encodeWithSignature("isMinter(address)", account)
        );
        require(success, "Failed to read isMinter");
        bool isMinter = abi.decode(data, (bool));
        if (!isMinter) {
            revert MinterRoleNotGranted();
        }
    }
}
