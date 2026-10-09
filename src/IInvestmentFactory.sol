// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IInvestment} from "./IInvestment.sol";

interface IInvestmentFactory {
    error InvestmentFactory__AddressesDiffer();

    event InvestmentCreated(
        string _name,
        address indexed investmentAddress,
        uint256 totalInvestment,
        uint256 minInvestment,
        uint256 deadline,
        address indexed receiver
    );

    /// @notice deploy a new escrow contract. The escrow will hold all the funds. The buyer is whoever calls this function.
    /// @param _name the name of the investment, also needed for salt generation.
    /// @param _totalInvestment the maximum investment needed for the project.
    /// @param _minTotalInvestment the minimum investment needed for the project goals.
    /// @param _deadline the deadline in unix timestamp (block.timestamp) to collect investment.
    /// @param _receiver the address of the funds collector.
    /// @param _initialOwner the address of the owner for the smart contract.
    /// @param _investmentHelper parent contract for all investments
    /// @param _restrictedToken address of the restricted (KYC-gated) token used for settlement, ROI and refunds
    /// @return the address of the newly deployed investment contract.
    function newInvestment(
        string memory _name,
        uint256 _totalInvestment,
        uint256 _minTotalInvestment,
        uint256 _deadline,
        address _receiver,
        address _initialOwner,
        address _investmentHelper,
        address _restrictedToken
    ) external returns (IInvestment);
}
