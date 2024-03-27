interface IDisputeManager {
    function getVerifierCut() external view returns (uint256);
    function getDisputePeriod() external view returns (uint64);
}
