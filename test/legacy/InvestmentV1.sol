// SPDX-License-Identifier: UNLICENSED
// Pre-fix copy, kept only so tests can demonstrate the bugs fixed in src/Investment.sol.
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IInvestment} from "../../src/IInvestment.sol";

contract InvestmentV1 is IInvestment, Ownable {
    string public name;
    uint256 public totalInvestment;
    uint256 public minTotalInvestment;
    uint256 public totalInvested;
    uint256 public deadline;
    uint256 public roiPhase;
    address public investmentHelper;
    address public receiver;
    IERC20 public restrictedToken;

    mapping(uint256 => uint256) public roiPhaseDistributionAmount;
    mapping(address => uint256) public investments;
    address[] public investors;

    constructor(
        string memory _name,
        uint256 _totalInvestment,
        uint256 _minTotalInvestment,
        uint256 _deadline,
        address _receiver,
        address _initialOwner,
        address _investmentHelper,
        address _restrictedToken
    ) Ownable(_initialOwner) {
        name = _name;
        totalInvestment = _totalInvestment;
        minTotalInvestment = _minTotalInvestment;
        deadline = _deadline;
        investmentHelper = _investmentHelper;
        receiver = _receiver;
        restrictedToken = IERC20(_restrictedToken);
        //set the investment contract, owner, and receiver as admin in restrictedToken Contract
    }

    modifier onlyInvestmentHelper() {
        msg.sender == investmentHelper;
        _;
    }

    // Function to invest funds
    function invest(address _user, uint256 _amount) public onlyInvestmentHelper {
        if (_amount <= 0) {
            revert Investment__InvalidAmount();
        }
        if (totalInvested + _amount > totalInvestment) {
            revert Investment_ExceedsTarget();
        }
        if (getInvestmentStatus() != 0) {
            revert Investment_InvalidStatus(getInvestmentStatus(), 0);
        }
        if (investments[_user] == 0) {
            investors.push(_user);
        }
        investments[_user] += _amount;
        totalInvested += _amount;
    }

    // Function to calculate the distribution amount for an investor
    function calculateShare(uint256 _amount, uint256 _amountToBeDistributed) public view returns (uint256) {
        if (totalInvestment == 0) return 0; // Avoid division by zero
        return ((_amount * _amountToBeDistributed) * 1e18) / totalInvestment;
    }

    function autoRefund(uint256 _start, uint256 _end) external onlyOwner {
        if (getInvestmentStatus() != 2) {
            revert Investment_InvalidStatus(getInvestmentStatus(), 2);
        }
        (address[] memory _investors, uint256[] memory _amounts) = getInvestorsWithAmounts();
        for (uint256 i = _start; i <= _end; i++) {
            restrictedToken.transfer(_investors[i], _amounts[i]);
        }
        emit Refunded(_start, _end);
    }

    function withdrawAccidentalTokens(address _tokenAddress, uint256 _amount) public onlyOwner {
        IERC20(_tokenAddress).transfer(owner(), _amount);
    }

    function withdrawAccidentalNative(uint256 _amount) public payable onlyOwner {
        (bool sent,) = payable(owner()).call{value: _amount}(""); // Returns false on failure
        require(sent, "Failed to send Ether");
    }

    function setROIPhaseAndDistributionAmount(uint256 _phase, uint256 _distributionAmount) external onlyOwner {
        require(roiPhaseDistributionAmount[_phase] == 0, "Distribution Amount already set!");
        roiPhase = _phase;
        roiPhaseDistributionAmount[_phase] = _distributionAmount;
        restrictedToken.transferFrom(owner(), address(this), _distributionAmount);
        emit ROIPhaseAndDistributionAmount(_phase, _distributionAmount);
    }

    function airdropROI(uint256 _start, uint256 _end) external onlyOwner {
        uint256 _amountToBeDistributed = roiPhaseDistributionAmount[roiPhase];
        if (getInvestmentStatus() != 1) {
            revert Investment_InvalidStatus(getInvestmentStatus(), 1);
        }

        if (_amountToBeDistributed <= 0) {
            revert Investment_DistributionAmountNotSet();
        }
        (address[] memory _investors, uint256[] memory _amounts) = getInvestorsWithAmounts();

        for (uint256 i = _start; i <= _end; i++) {
            uint256 _amount = calculateShare(_amounts[i], _amountToBeDistributed) / 1e18;
            restrictedToken.transfer(_investors[i], _amount);
        }
        emit ROIAirdropped(roiPhase, _start, _end, _amountToBeDistributed);
    }

    // Function to get an investor's balance
    function getInvestment(address investor) public view returns (uint256) {
        return investments[investor];
    }

    // Function to get all investors
    function getAllInvestors() external view returns (address[] memory) {
        return investors;
    }

    // Function to get all investors and their invested amounts
    function getInvestorsWithAmounts() public view returns (address[] memory, uint256[] memory) {
        uint256[] memory amounts = new uint256[](investors.length);

        for (uint256 i = 0; i < investors.length; i++) {
            amounts[i] = investments[investors[i]];
        }

        return (investors, amounts);
    }

    function getInvestmentStatus() public view returns (uint256) {
        if (totalInvested < minTotalInvestment && block.timestamp >= deadline) {
            return 2;
        }
        if ((totalInvested >= minTotalInvestment && block.timestamp >= deadline) || totalInvested == totalInvestment) {
            return 1;
        }
        return 0;
    }

    function getReceiver() external view returns (address) {
        return receiver;
    }

    function getDistributionAmountInPhase(uint256 _phase) external view returns (uint256) {
        return roiPhaseDistributionAmount[_phase];
    }

    function getInvestorLength() external view returns (uint256) {
        return investors.length;
    }
}
