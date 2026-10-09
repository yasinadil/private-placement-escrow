// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IInvestmentHelper {
    event Invested(address indexed investmentAddress, address indexed investor, uint256 amount);

    /// @notice deploy a new escrow contract. The escrow will hold all the funds. The buyer is whoever calls this function.
    /// @param _investment address of the investment smart contract
    /// @param _amount the amount to be invested
    function invest(address _investment, uint256 _amount) external;
}
