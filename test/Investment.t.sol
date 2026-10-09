// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RestrictedToken} from "../src/RestrictedToken.sol";
import {InvestmentFactory} from "../src/InvestmentFactory.sol";
import {InvestmentHelper} from "../src/InvestmentHelper.sol";
import {Investment} from "../src/Investment.sol";
import {IInvestment} from "../src/IInvestment.sol";
import {IInvestmentFactory} from "../src/IInvestmentFactory.sol";

contract InvestmentTest is Test {
    RestrictedToken internal token;
    InvestmentFactory internal factory;
    InvestmentHelper internal helper;
    Investment internal offering;

    address internal admin = makeAddr("admin"); // platform multisig
    address internal issuer = makeAddr("issuer"); // offering owner
    address internal receiver = makeAddr("receiver"); // issuer's settlement account
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant CAP = 1_000e18;
    uint256 internal constant SOFT_CAP = 800e18;
    uint256 internal deadline;

    function setUp() public {
        deadline = block.timestamp + 30 days;
        vm.startPrank(admin);
        token = new RestrictedToken(admin);
        factory = new InvestmentFactory(admin, address(token));
        token.setFactoryContract(address(factory));
        helper = new InvestmentHelper(address(token));
        token.setAdmin(issuer); // issuer funds returns and refunds
        offering = Investment(
            address(
                factory.newInvestment(
                    "Series A", CAP, SOFT_CAP, deadline, receiver, issuer, address(helper), address(token)
                )
            )
        );

        address[4] memory users = [alice, bob, carol, attacker];
        for (uint256 i; i < users.length; i++) {
            token.mint(users[i], 10_000e18);
        }
        token.mint(issuer, 100_000e18);
        vm.stopPrank();

        for (uint256 i; i < users.length; i++) {
            vm.prank(users[i]);
            token.approve(address(helper), type(uint256).max);
        }
        vm.prank(issuer);
        token.approve(address(offering), type(uint256).max);
    }

    function _invest(address who, uint256 amount) internal {
        vm.prank(who);
        helper.invest(address(offering), amount);
    }

    // ---------------------------------------------------------------- subscribing

    function test_investThroughHelperPaysReceiver() public {
        _invest(alice, 300e18);
        assertEq(offering.getInvestment(alice), 300e18);
        assertEq(offering.totalInvested(), 300e18);
        assertEq(token.balanceOf(receiver), 300e18, "funds settle straight to the issuer");
        assertEq(offering.getInvestorLength(), 1);

        _invest(alice, 100e18);
        assertEq(offering.getInvestorLength(), 1, "repeat investor listed once");
    }

    function test_directInvestIsRejected() public {
        vm.prank(attacker);
        vm.expectRevert(IInvestment.Investment__NotHelper.selector);
        offering.invest(attacker, 200e18);
    }

    function test_invest_validation() public {
        vm.prank(alice);
        vm.expectRevert(IInvestment.Investment__InvalidAmount.selector);
        helper.invest(address(offering), 0);

        _invest(alice, 900e18);
        vm.prank(bob);
        vm.expectRevert(IInvestment.Investment_ExceedsTarget.selector);
        helper.invest(address(offering), 200e18);

        _invest(bob, 100e18); // hits the hard cap: status becomes successful
        vm.prank(carol);
        vm.expectRevert(IInvestment.Investment_ExceedsTarget.selector);
        helper.invest(address(offering), 1);
    }

    function test_cannotInvestAfterDeadline() public {
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IInvestment.Investment_InvalidStatus.selector, 2, 0));
        helper.invest(address(offering), 1e18);
    }

    function test_statusMachine() public {
        assertEq(offering.getInvestmentStatus(), 0, "open");
        _invest(alice, SOFT_CAP - 1);
        vm.warp(deadline);
        assertEq(offering.getInvestmentStatus(), 2, "below soft cap at deadline: failed");
    }

    function test_statusSuccessAtSoftCap() public {
        _invest(alice, SOFT_CAP);
        assertEq(offering.getInvestmentStatus(), 0, "still open before deadline");
        vm.warp(deadline);
        assertEq(offering.getInvestmentStatus(), 1);
    }

    // ---------------------------------------------------------------- returns

    function test_roiIsProRataToActualRaise() public {
        _invest(alice, 600e18);
        _invest(bob, 200e18); // raise closes at the 800 soft cap, not the 1000 hard cap
        vm.warp(deadline);

        vm.startPrank(issuer);
        offering.setROIPhaseAndDistributionAmount(1, 80e18);
        offering.airdropROI(0, 1);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 10_000e18 - 600e18 + 60e18);
        assertEq(token.balanceOf(bob), 10_000e18 - 200e18 + 20e18);
        assertEq(token.balanceOf(address(offering)), 0, "whole phase distributed");
    }

    function test_airdropIsIdempotent() public {
        _invest(alice, 500e18);
        _invest(bob, 500e18);
        vm.startPrank(issuer);
        offering.setROIPhaseAndDistributionAmount(1, 100e18);
        offering.airdropROI(0, 1);
        offering.airdropROI(0, 1);
        offering.airdropROI(1, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10_000e18 - 500e18 + 50e18);
        assertEq(token.balanceOf(bob), 10_000e18 - 500e18 + 50e18);
    }

    function test_multiplePhases() public {
        _invest(alice, 1_000e18);
        vm.startPrank(issuer);
        offering.setROIPhaseAndDistributionAmount(1, 10e18);
        offering.airdropROI(0, 0);
        offering.setROIPhaseAndDistributionAmount(2, 30e18);
        offering.airdropROI(0, 0);
        vm.expectRevert("Distribution Amount already set!");
        offering.setROIPhaseAndDistributionAmount(2, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10_000e18 - 1_000e18 + 40e18);
        assertEq(offering.getDistributionAmountInPhase(2), 30e18);
    }

    function test_airdrop_guards() public {
        _invest(alice, 100e18);
        vm.startPrank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IInvestment.Investment_InvalidStatus.selector, 0, 1));
        offering.airdropROI(0, 0);
        vm.stopPrank();

        _invest(bob, 900e18);
        vm.startPrank(issuer);
        vm.expectRevert(IInvestment.Investment_DistributionAmountNotSet.selector);
        offering.airdropROI(0, 1);
        offering.setROIPhaseAndDistributionAmount(1, 1e18);
        vm.expectRevert(IInvestment.Investment__InvalidRange.selector);
        offering.airdropROI(0, 2);
        vm.expectRevert(IInvestment.Investment__InvalidRange.selector);
        offering.airdropROI(1, 0);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        offering.airdropROI(0, 1);
    }

    // ---------------------------------------------------------------- refunds

    function test_refundsOnFailedRaiseAreIdempotent() public {
        _invest(alice, 300e18);
        _invest(bob, 100e18);
        vm.warp(deadline);

        vm.prank(issuer);
        token.transfer(address(offering), 400e18); // issuer funds the refund pool

        vm.startPrank(issuer);
        offering.autoRefund(0, 1);
        offering.autoRefund(0, 1);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 10_000e18);
        assertEq(token.balanceOf(bob), 10_000e18);
        assertTrue(offering.refunded(alice));
    }

    function test_refundOnlyWhenFailed() public {
        _invest(alice, 300e18);
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IInvestment.Investment_InvalidStatus.selector, 0, 2));
        offering.autoRefund(0, 0);
    }

    // ---------------------------------------------------------------- admin

    function test_withdrawAccidentalFunds() public {
        vm.prank(issuer);
        token.transfer(address(offering), 5e18);
        vm.deal(address(offering), 1 ether);

        vm.startPrank(issuer);
        offering.withdrawAccidentalTokens(address(token), 5e18);
        offering.withdrawAccidentalNative(1 ether);
        vm.stopPrank();
        assertEq(issuer.balance, 1 ether);
    }

    function test_views() public {
        _invest(alice, 10e18);
        _invest(bob, 20e18);
        (address[] memory who, uint256[] memory amounts) = offering.getInvestorsWithAmounts();
        assertEq(who.length, 2);
        assertEq(amounts[1], 20e18);
        assertEq(offering.getAllInvestors()[0], alice);
        assertEq(offering.getReceiver(), receiver);
        assertEq(offering.calculateShare(10e18, 30e18), 10e18 * 1e18);
    }

    // ---------------------------------------------------------------- factory

    function test_factoryPredictsCreate2Address() public {
        bytes32 salt = bytes32(uint256(keccak256(abi.encodePacked("Series B"))));
        address predicted = factory.computeEscrowAddress(
            type(Investment).creationCode,
            address(factory),
            uint256(salt),
            "Series B",
            CAP,
            SOFT_CAP,
            deadline,
            receiver,
            issuer,
            address(helper),
            address(token)
        );
        vm.prank(admin);
        IInvestment created = factory.newInvestment(
            "Series B", CAP, SOFT_CAP, deadline, receiver, issuer, address(helper), address(token)
        );
        assertEq(address(created), predicted);
        assertTrue(token.admin(address(created)), "offering can pay out the restricted token");
    }

    function test_factoryGuards() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        factory.newInvestment("X", CAP, SOFT_CAP, deadline, receiver, issuer, address(helper), address(token));

        vm.prank(admin);
        vm.expectRevert(); // CREATE2 collision: names are unique per factory
        factory.newInvestment("Series A", CAP, SOFT_CAP, deadline, receiver, issuer, address(helper), address(token));
    }

    // ---------------------------------------------------------------- restricted token

    function test_tokenOnlyMovesThroughAdmins() public {
        vm.prank(alice);
        vm.expectRevert("Transfers only allowed to admin");
        token.transfer(bob, 1);

        vm.prank(alice);
        token.transfer(receiver, 1); // receiver is an admin
        assertEq(token.balanceOf(receiver), 1);

        address[] memory list = new address[](1);
        list[0] = receiver;
        vm.prank(admin);
        token.revokeAdmin(list);
        vm.prank(alice);
        vm.expectRevert("Transfers only allowed to admin");
        token.transfer(receiver, 1);
    }

    function test_tokenAdminRoles() public {
        vm.prank(alice);
        vm.expectRevert("This function can only be called by owner or the factory contract.");
        token.setAdmin(alice);

        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1);
    }

    // ---------------------------------------------------------------- fuzz

    /// Payouts always sum to the phase amount, minus at most 1 wei of rounding per investor.
    function testFuzz_payoutsConserveDistribution(uint96[3] memory amounts, uint96 distribution) public {
        vm.prank(admin);
        offering = Investment(
            address(factory.newInvestment("Fuzz", CAP, 1, deadline, receiver, issuer, address(helper), address(token)))
        );
        vm.prank(issuer);
        token.approve(address(offering), type(uint256).max);

        address[3] memory users = [alice, bob, carol];
        for (uint256 i; i < 3; i++) {
            _invest(users[i], bound(amounts[i], 1, 300e18));
        }
        uint256 d = bound(distribution, 1, 50_000e18);
        vm.warp(deadline);

        uint256 before = token.balanceOf(issuer);
        vm.startPrank(issuer);
        offering.setROIPhaseAndDistributionAmount(1, d);
        offering.airdropROI(0, 2);
        vm.stopPrank();
        assertEq(before - token.balanceOf(issuer), d);

        uint256 left = token.balanceOf(address(offering));
        assertLe(left, 3, "at most 1 wei of rounding dust per investor");
    }
}
