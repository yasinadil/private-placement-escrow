// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IInvestment {
    //Errors
    error Investment__InvalidAmount();
    error Investment_ExceedsTarget();
    error Investment_InvalidStatus(uint256 state, uint256 expected_state);
    error Investment_DistributionAmountNotSet();
    error Investment__NotHelper();
    error Investment__InvalidRange();

    /// Events
    event ROIPhaseAndDistributionAmount(uint256 roiPhase, uint256 distributionAmount);
    event ROIAirdropped(uint256 roiPhase, uint256 start, uint256 end, uint256 distributionAmount);
    event Refunded(uint256 start, uint256 end);

    //state mutating functions
    function invest(address _user, uint256 _amount) external;
    function autoRefund(uint256 _start, uint256 _end) external;
    function withdrawAccidentalTokens(address _tokenAddress, uint256 _amount) external;
    function withdrawAccidentalNative(uint256 _amount) external payable;
    function setROIPhaseAndDistributionAmount(uint256 _phase, uint256 _distributionAmount) external;
    function airdropROI(uint256 _start, uint256 _end) external;

    /////////////////////
    // View functions
    /////////////////////

    function calculateShare(uint256 _amount, uint256 _amountToBeDistributed) external view returns (uint256);
    function getInvestment(address investor) external view returns (uint256);
    function getAllInvestors() external view returns (address[] memory);
    function getInvestorsWithAmounts() external view returns (address[] memory, uint256[] memory);
    function getInvestmentStatus() external view returns (uint256);
    function getReceiver() external view returns (address);
    function getDistributionAmountInPhase(uint256 _phase) external view returns (uint256);
}
