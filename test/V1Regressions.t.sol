// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RestrictedToken} from "../src/RestrictedToken.sol";
import {InvestmentHelper} from "../src/InvestmentHelper.sol";
import {Investment} from "../src/Investment.sol";
import {IInvestment} from "../src/IInvestment.sol";
import {InvestmentV1} from "./legacy/InvestmentV1.sol";

/// @notice Each test runs one scenario against the pre-fix contract (v1) and the fixed one (v2).
contract V1RegressionsTest is Test {
    RestrictedToken internal token;
    InvestmentHelper internal helper;
    InvestmentV1 internal v1;
    Investment internal v2;

    address internal admin = makeAddr("admin");
    address internal receiver = makeAddr("receiver");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant CAP = 1_000e18;
    uint256 internal constant SOFT_CAP = 800e18;
    uint256 internal deadline;

    function setUp() public {
        deadline = block.timestamp + 30 days;
        vm.startPrank(admin);
        token = new RestrictedToken(admin);
        helper = new InvestmentHelper(address(token));
        v1 = new InvestmentV1("v1", CAP, SOFT_CAP, deadline, receiver, admin, address(helper), address(token));
        v2 = new Investment("v2", CAP, SOFT_CAP, deadline, receiver, admin, address(helper), address(token));
        token.setAdmin(admin);
        token.setAdmin(receiver);
        token.setAdmin(address(v1));
        token.setAdmin(address(v2));
        token.mint(admin, 1_000_000e18);
        token.mint(alice, 10_000e18);
        token.mint(bob, 10_000e18);
        token.approve(address(v1), type(uint256).max);
        token.approve(address(v2), type(uint256).max);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(helper), type(uint256).max);
        vm.prank(bob);
        token.approve(address(helper), type(uint256).max);
    }

    /// Bug 1 (critical): `onlyInvestmentHelper` never reverted, so anyone could record a
    /// subscription without paying, then collect a pro-rata share of every distribution
    /// (or a refund), and could also fill the cap to close the raise to real investors.
    function test_bug1_freeSubscriptionStealsReturns() public {
        vm.prank(alice);
        helper.invest(address(v1), 800e18); // alice pays 800
        vm.prank(attacker);
        v1.invest(attacker, 200e18); // attacker pays nothing and fills the cap
        assertEq(v1.getInvestmentStatus(), 1, "v1: raise force-closed by attacker");
        assertEq(token.balanceOf(attacker), 0);

        vm.startPrank(admin);
        v1.setROIPhaseAndDistributionAmount(1, 100e18);
        v1.airdropROI(0, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(attacker), 20e18, "v1: attacker took 20% of returns for free");

        vm.prank(attacker);
        vm.expectRevert(IInvestment.Investment__NotHelper.selector);
        v2.invest(attacker, 200e18);
    }

    /// Bug 2: shares were divided by the hard cap, so a raise closing between soft and hard cap
    /// under-distributed every phase (here 80 of 100).
    function test_bug2_underDistributionBelowHardCap() public {
        vm.startPrank(alice);
        helper.invest(address(v1), 800e18);
        helper.invest(address(v2), 800e18);
        vm.stopPrank();
        vm.warp(deadline);

        uint256 a0 = token.balanceOf(alice);
        vm.startPrank(admin);
        v1.setROIPhaseAndDistributionAmount(1, 100e18);
        v1.airdropROI(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) - a0, 80e18, "v1: only 80% of the phase reached investors");

        a0 = token.balanceOf(alice);
        vm.startPrank(admin);
        v2.setROIPhaseAndDistributionAmount(1, 100e18);
        v2.airdropROI(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) - a0, 100e18, "v2: full phase distributed");
    }

    /// Bug 3: re-running a batch (e.g. an operator retry after a timeout) paid the same investors
    /// again out of everyone else's share, so later batches ran dry.
    function test_bug3_retriedBatchPaysTwice() public {
        vm.prank(alice);
        helper.invest(address(v1), 500e18);
        vm.prank(bob);
        helper.invest(address(v1), 500e18);

        uint256 a0 = token.balanceOf(alice);
        vm.startPrank(admin);
        v1.setROIPhaseAndDistributionAmount(1, 100e18);
        v1.airdropROI(0, 0);
        v1.airdropROI(0, 0); // retry of the same batch
        vm.expectRevert(); // bob's share is gone
        v1.airdropROI(1, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) - a0, 100e18, "v1: alice took bob's share too");

        vm.prank(alice);
        helper.invest(address(v2), 500e18);
        vm.prank(bob);
        helper.invest(address(v2), 500e18);
        a0 = token.balanceOf(alice);
        uint256 b0 = token.balanceOf(bob);
        vm.startPrank(admin);
        v2.setROIPhaseAndDistributionAmount(1, 100e18);
        v2.airdropROI(0, 0);
        v2.airdropROI(0, 0);
        v2.airdropROI(1, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) - a0, 50e18, "v2: paid once");
        assertEq(token.balanceOf(bob) - b0, 50e18, "v2: bob still paid");
    }
}
