// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IInvestmentHelper} from "./IInvestmentHelper.sol";
import {IInvestment} from "./IInvestment.sol";

contract InvestmentHelper is IInvestmentHelper, ReentrancyGuard {
    IERC20 public settlementToken;

    constructor(address _settlementToken) {
        settlementToken = IERC20(_settlementToken);
    }

    // Function to invest funds
    function invest(address _investment, uint256 _amount) public nonReentrant {
        address receiver = IInvestment(_investment).getReceiver();
        IInvestment(_investment).invest(msg.sender, _amount);
        settlementToken.transferFrom(msg.sender, receiver, _amount);
        emit Invested(_investment, msg.sender, _amount);
    }
}
