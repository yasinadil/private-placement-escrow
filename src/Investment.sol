// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IInvestment} from "./IInvestment.sol";

/// @title Investment
/// @notice One private-placement offering: a capped raise with a soft cap (`minTotalInvestment`) and a
///         deadline. Investors subscribe through the `InvestmentHelper`, which moves the settlement
///         token straight to the issuer's `receiver`. On success the issuer distributes returns in
///         phases, pro-rata to subscriptions; on failure investors are refunded.
/// @dev Status: 0 = open, 1 = successful (cap hit, or soft cap met at deadline), 2 = failed.
contract Investment is IInvestment, Ownable {
    using SafeERC20 for IERC20;

    string public name;
    uint256 public totalInvestment; // hard cap
    uint256 public minTotalInvestment; // soft cap
    uint256 public totalInvested;
    uint256 public deadline;
    uint256 public roiPhase;
    address public investmentHelper;
    address public receiver;
    IERC20 public restrictedToken;

    mapping(uint256 => uint256) public roiPhaseDistributionAmount;
    mapping(address => uint256) public investments;
    address[] public investors;

    /// @notice phase => investor => already paid. Makes batched airdrops idempotent.
    mapping(uint256 => mapping(address => bool)) public roiPaid;
    /// @notice investor => already refunded. Makes batched refunds idempotent.
    mapping(address => bool) public refunded;

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
    }

    /// @dev v1 evaluated `msg.sender == investmentHelper;` without requiring it, so anyone could call
    ///      `invest` directly and record a subscription without paying.
    modifier onlyInvestmentHelper() {
        if (msg.sender != investmentHelper) revert Investment__NotHelper();
        _;
    }

    /// @notice Records a subscription. Only callable by the helper, which collects payment first.
    function invest(address _user, uint256 _amount) public onlyInvestmentHelper {
        if (_amount == 0) revert Investment__InvalidAmount();
        if (totalInvested + _amount > totalInvestment) revert Investment_ExceedsTarget();
        uint256 status = getInvestmentStatus();
        if (status != 0) revert Investment_InvalidStatus(status, 0);

        if (investments[_user] == 0) investors.push(_user);
        investments[_user] += _amount;
        totalInvested += _amount;
    }

    /// @notice An investor's share of `_amountToBeDistributed`, scaled by 1e18.
    /// @dev v1 divided by the hard cap (`totalInvestment`), so a raise that closed between soft and
    ///      hard cap only ever distributed `totalInvested / totalInvestment` of each phase.
    function calculateShare(uint256 _amount, uint256 _amountToBeDistributed) public view returns (uint256) {
        if (totalInvested == 0) return 0;
        return (_amount * _amountToBeDistributed * 1e18) / totalInvested;
    }

    /// @notice Refunds investors `[_start, _end]` of a failed raise. Safe to re-run over any range.
    function autoRefund(uint256 _start, uint256 _end) external onlyOwner {
        uint256 status = getInvestmentStatus();
        if (status != 2) revert Investment_InvalidStatus(status, 2);
        _checkRange(_start, _end);

        for (uint256 i = _start; i <= _end; i++) {
            address investor = investors[i];
            if (refunded[investor]) continue;
            refunded[investor] = true;
            restrictedToken.safeTransfer(investor, investments[investor]);
        }
        emit Refunded(_start, _end);
    }

    function withdrawAccidentalTokens(address _tokenAddress, uint256 _amount) public onlyOwner {
        IERC20(_tokenAddress).safeTransfer(owner(), _amount);
    }

    function withdrawAccidentalNative(uint256 _amount) public payable onlyOwner {
        (bool sent,) = payable(owner()).call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice Opens a distribution phase and pulls its funds from the owner.
    function setROIPhaseAndDistributionAmount(uint256 _phase, uint256 _distributionAmount) external onlyOwner {
        require(roiPhaseDistributionAmount[_phase] == 0, "Distribution Amount already set!");
        roiPhase = _phase;
        roiPhaseDistributionAmount[_phase] = _distributionAmount;
        restrictedToken.safeTransferFrom(owner(), address(this), _distributionAmount);
        emit ROIPhaseAndDistributionAmount(_phase, _distributionAmount);
    }

    /// @notice Pays investors `[_start, _end]` their share of the current phase. Idempotent per
    ///         investor and phase, so overlapping or repeated batches can't double-pay (v1 could).
    function airdropROI(uint256 _start, uint256 _end) external onlyOwner {
        uint256 phase = roiPhase;
        uint256 toDistribute = roiPhaseDistributionAmount[phase];
        uint256 status = getInvestmentStatus();
        if (status != 1) revert Investment_InvalidStatus(status, 1);
        if (toDistribute == 0) revert Investment_DistributionAmountNotSet();
        _checkRange(_start, _end);

        for (uint256 i = _start; i <= _end; i++) {
            address investor = investors[i];
            if (roiPaid[phase][investor]) continue;
            roiPaid[phase][investor] = true;
            uint256 amount = calculateShare(investments[investor], toDistribute) / 1e18;
            restrictedToken.safeTransfer(investor, amount);
        }
        emit ROIAirdropped(phase, _start, _end, toDistribute);
    }

    function getInvestment(address investor) public view returns (uint256) {
        return investments[investor];
    }

    function getAllInvestors() external view returns (address[] memory) {
        return investors;
    }

    function getInvestorsWithAmounts() public view returns (address[] memory, uint256[] memory) {
        uint256[] memory amounts = new uint256[](investors.length);
        for (uint256 i = 0; i < investors.length; i++) {
            amounts[i] = investments[investors[i]];
        }
        return (investors, amounts);
    }

    function getInvestmentStatus() public view returns (uint256) {
        if (totalInvested < minTotalInvestment && block.timestamp >= deadline) return 2;
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

    function _checkRange(uint256 _start, uint256 _end) private view {
        if (_start > _end || _end >= investors.length) revert Investment__InvalidRange();
    }
}
