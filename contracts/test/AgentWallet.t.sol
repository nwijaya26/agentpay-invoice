// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {InvoiceCheckout} from "../src/InvoiceCheckout.sol";
import {MockUSD8} from "../src/mocks/MockUSD8.sol";

contract AgentWalletTest is Test {
    MockUSD8 token;
    AgentWallet wallet;
    InvoiceCheckout checkout;
    address owner = makeAddr("owner");
    address agent = makeAddr("agent");
    address payee = makeAddr("payee");
    address stranger = makeAddr("stranger");

    uint256 constant CAP = 100e6; // 100 tUSD8 per period
    uint64 constant PERIOD = 1 days;
    uint64 expiry;

    function setUp() public {
        token = new MockUSD8();
        wallet = new AgentWallet(IERC20(address(token)), owner);
        checkout = new InvoiceCheckout();
        expiry = uint64(block.timestamp + 7 days);
        token.mint(owner, 1_000e6);
    }

    function _configure() internal {
        vm.prank(owner);
        wallet.configureSession(agent, CAP, PERIOD, expiry);
    }

    function _fund(uint256 amount) internal {
        vm.startPrank(owner);
        token.approve(address(wallet), amount);
        wallet.fund(amount);
        vm.stopPrank();
    }

    function _allowPayee() internal {
        vm.prank(owner);
        wallet.setPayeeAllowed(payee, true);
    }

    function _setupReady(uint256 fundAmount) internal {
        _configure();
        _allowPayee();
        _fund(fundAmount);
    }

    // ---------- configuration ----------

    function test_configure_setsSessionAndEmits() public {
        vm.expectEmit(true, false, false, true, address(wallet));
        emit AgentWallet.SessionConfigured(agent, CAP, PERIOD, expiry);
        _configure();
        assertEq(wallet.agent(), agent);
        assertEq(wallet.budgetCap(), CAP);
        assertEq(wallet.remainingBudget(), CAP);
        assertTrue(wallet.sessionActive());
    }

    function test_configure_revertsForNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        wallet.configureSession(agent, CAP, PERIOD, expiry);
    }

    function test_configure_revertsOnBadPolicy() public {
        vm.startPrank(owner);
        vm.expectRevert(AgentWallet.InvalidPolicy.selector);
        wallet.configureSession(agent, 0, PERIOD, expiry);
        vm.expectRevert(AgentWallet.InvalidPolicy.selector);
        wallet.configureSession(agent, CAP, 0, expiry);
        vm.expectRevert(AgentWallet.InvalidPolicy.selector);
        wallet.configureSession(agent, CAP, PERIOD, uint64(block.timestamp));
        vm.expectRevert(AgentWallet.ZeroAddress.selector);
        wallet.configureSession(address(0), CAP, PERIOD, expiry);
        vm.stopPrank();
    }

    // ---------- fund / withdraw ----------

    function test_fundAndWithdraw_ownerOnly() public {
        _configure();
        _fund(200e6);
        assertEq(token.balanceOf(address(wallet)), 200e6);

        vm.prank(stranger);
        vm.expectRevert();
        wallet.withdraw(stranger, 1e6);

        vm.prank(owner);
        wallet.withdraw(owner, 50e6);
        assertEq(token.balanceOf(address(wallet)), 150e6);
        assertEq(token.balanceOf(owner), 1_000e6 - 200e6 + 50e6);
    }

    // ---------- pay ----------

    function test_pay_withinBudget() public {
        _setupReady(200e6);
        vm.prank(agent);
        vm.expectEmit(true, true, false, true, address(wallet));
        emit AgentWallet.AgentPaid(agent, payee, 40e6, 40e6);
        wallet.pay(payee, 40e6);

        assertEq(token.balanceOf(payee), 40e6);
        assertEq(wallet.spentInPeriod(), 40e6);
        assertEq(wallet.remainingBudget(), CAP - 40e6);
    }

    function test_pay_revertsOverBudget() public {
        _setupReady(500e6);
        vm.startPrank(agent);
        wallet.pay(payee, 60e6);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.BudgetExceeded.selector, CAP - 60e6, 50e6));
        wallet.pay(payee, 50e6);
        vm.stopPrank();
    }

    function test_pay_revertsForNonAllowlistedPayee() public {
        _setupReady(200e6);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.PayeeNotAllowed.selector, stranger));
        wallet.pay(stranger, 1e6);
    }

    function test_pay_revertsForNonAgent() public {
        _setupReady(200e6);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.NotAgent.selector, stranger));
        wallet.pay(payee, 1e6);
        // Not even the owner can spend as the agent.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.NotAgent.selector, owner));
        wallet.pay(payee, 1e6);
    }

    function test_pay_revertsWithoutSession() public {
        vm.prank(agent);
        vm.expectRevert(AgentWallet.NoSession.selector);
        wallet.pay(payee, 1e6);
    }

    function test_pay_revertsAfterExpiry() public {
        _setupReady(200e6);
        vm.warp(expiry + 1);
        assertFalse(wallet.sessionActive());
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.SessionExpired.selector, expiry));
        wallet.pay(payee, 1e6);
    }

    function test_pay_atExactExpiry_succeeds() public {
        _setupReady(200e6);
        vm.warp(expiry);
        vm.prank(agent);
        wallet.pay(payee, 1e6);
        assertEq(token.balanceOf(payee), 1e6);
    }

    function test_budget_rollsOverNextPeriod() public {
        _setupReady(500e6);
        vm.startPrank(agent);
        wallet.pay(payee, CAP); // spend the whole period budget
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.BudgetExceeded.selector, 0, 1e6));
        wallet.pay(payee, 1e6);
        vm.warp(block.timestamp + PERIOD);
        assertEq(wallet.remainingBudget(), CAP);
        wallet.pay(payee, 25e6);
        vm.stopPrank();
        assertEq(wallet.spentInPeriod(), 25e6);
        assertEq(token.balanceOf(payee), CAP + 25e6);
    }

    // ---------- revoke ----------

    function test_revoke_blocksPaymentsInstantly() public {
        _setupReady(200e6);
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(wallet));
        emit AgentWallet.SessionRevoked(agent);
        wallet.revoke();

        assertFalse(wallet.sessionActive());
        vm.prank(agent);
        vm.expectRevert(AgentWallet.SessionRevokedError.selector);
        wallet.pay(payee, 1e6);
    }

    function test_revoke_thenReconfigure_restoresPayments() public {
        _setupReady(200e6);
        vm.prank(owner);
        wallet.revoke();
        _configure();
        assertTrue(wallet.sessionActive());
        vm.prank(agent);
        wallet.pay(payee, 1e6);
        assertEq(token.balanceOf(payee), 1e6);
    }

    function test_revoke_revertsForNonOwner() public {
        _configure();
        vm.prank(agent);
        vm.expectRevert();
        wallet.revoke();
    }

    // ---------- payInvoice integration ----------

    bytes32 constant INV = keccak256("invoice-agent-1");

    function _createInvoice(uint256 amount) internal returns (bytes32) {
        vm.prank(owner);
        checkout.createInvoice(
            INV, payee, address(token), amount, uint64(block.timestamp + 1 days), bytes32(0)
        );
        return INV;
    }

    function test_payInvoice_paysOpenInvoice() public {
        _setupReady(200e6);
        _createInvoice(30e6);
        vm.prank(agent);
        vm.expectEmit(true, true, true, true, address(wallet));
        emit AgentWallet.AgentPaidInvoice(agent, INV, payee, 30e6);
        wallet.payInvoice(checkout, INV);

        assertTrue(checkout.isPaid(INV));
        assertEq(checkout.invoiceOf(INV).payer, address(wallet));
        assertEq(token.balanceOf(payee), 30e6);
        assertEq(wallet.spentInPeriod(), 30e6);
        assertEq(token.allowance(address(wallet), address(checkout)), 0);
    }

    function test_payInvoice_revertsOverBudget() public {
        _setupReady(500e6);
        _createInvoice(CAP + 1e6);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.BudgetExceeded.selector, CAP, CAP + 1e6));
        wallet.payInvoice(checkout, INV);
        assertFalse(checkout.isPaid(INV));
    }

    function test_payInvoice_revertsForNonAllowlistedPayee() public {
        _configure();
        _fund(200e6); // payee NOT allowlisted this time
        _createInvoice(10e6);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.PayeeNotAllowed.selector, payee));
        wallet.payInvoice(checkout, INV);
    }

    function test_payInvoice_revertsAfterRevoke() public {
        _setupReady(200e6);
        _createInvoice(10e6);
        vm.prank(owner);
        wallet.revoke();
        vm.prank(agent);
        vm.expectRevert(AgentWallet.SessionRevokedError.selector);
        wallet.payInvoice(checkout, INV);
    }

    function test_payInvoice_revertsOnPaidInvoice() public {
        _setupReady(200e6);
        _createInvoice(10e6);
        vm.prank(agent);
        wallet.payInvoice(checkout, INV);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.InvoiceNotOpen.selector, INV));
        wallet.payInvoice(checkout, INV);
    }
}
