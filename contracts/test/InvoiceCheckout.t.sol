// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InvoiceCheckout} from "../src/InvoiceCheckout.sol";
import {MockUSD8} from "../src/mocks/MockUSD8.sol";
import {Signing} from "./Signing.sol";

contract InvoiceCheckoutTest is Test {
    MockUSD8 token;
    InvoiceCheckout checkout;
    address creator = makeAddr("creator");
    address payee = makeAddr("payee");
    address payer;
    uint256 payerKey;
    address relayer = makeAddr("relayer");
    address stranger = makeAddr("stranger");

    bytes32 constant INV = keccak256("invoice-1");
    bytes32 constant REF = keccak256("PO-2026-001");
    uint256 constant AMOUNT = 25e6; // 25 tUSD8
    uint64 deadline;

    function setUp() public {
        (payer, payerKey) = makeAddrAndKey("payer");
        token = new MockUSD8();
        checkout = new InvoiceCheckout();
        deadline = uint64(block.timestamp + 1 days);
        token.mint(payer, 1_000e6);
        token.mint(stranger, 1_000e6);
    }

    function _create() internal {
        vm.prank(creator);
        checkout.createInvoice(INV, payee, address(token), AMOUNT, deadline, REF);
    }

    // ---------- createInvoice ----------

    function test_create_storesInvoiceAndEmits() public {
        vm.expectEmit(true, true, true, true, address(checkout));
        emit InvoiceCheckout.InvoiceCreated(INV, creator, payee, address(token), AMOUNT, deadline, REF);
        _create();

        InvoiceCheckout.Invoice memory inv = checkout.invoiceOf(INV);
        assertEq(inv.creator, creator);
        assertEq(inv.payee, payee);
        assertEq(inv.token, address(token));
        assertEq(inv.amount, AMOUNT);
        assertEq(inv.deadline, deadline);
        assertEq(inv.ref, REF);
        assertEq(uint8(inv.status), uint8(InvoiceCheckout.Status.Open));
        assertEq(inv.payer, address(0));
        assertFalse(checkout.isPaid(INV));
    }

    function test_create_revertsOnZeroPayee() public {
        vm.prank(creator);
        vm.expectRevert(InvoiceCheckout.ZeroAddress.selector);
        checkout.createInvoice(INV, address(0), address(token), AMOUNT, deadline, REF);
    }

    function test_create_revertsOnZeroToken() public {
        vm.prank(creator);
        vm.expectRevert(InvoiceCheckout.ZeroAddress.selector);
        checkout.createInvoice(INV, payee, address(0), AMOUNT, deadline, REF);
    }

    function test_create_revertsOnZeroAmount() public {
        vm.prank(creator);
        vm.expectRevert(InvoiceCheckout.ZeroAmount.selector);
        checkout.createInvoice(INV, payee, address(token), 0, deadline, REF);
    }

    function test_create_revertsOnPastDeadline() public {
        vm.prank(creator);
        vm.expectRevert(InvoiceCheckout.InvalidDeadline.selector);
        checkout.createInvoice(INV, payee, address(token), AMOUNT, uint64(block.timestamp), REF);
    }

    function test_create_revertsOnDuplicateId() public {
        _create();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.InvoiceExists.selector, INV));
        checkout.createInvoice(INV, payee, address(token), AMOUNT, deadline, REF);
    }

    // ---------- pay (approve + call) ----------

    function test_pay_movesExactAmountAndRecords() public {
        _create();
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        vm.expectEmit(true, true, true, true, address(checkout));
        emit InvoiceCheckout.Paid(INV, payer, payee, AMOUNT);
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(payee), AMOUNT);
        assertEq(token.balanceOf(payer), 1_000e6 - AMOUNT);
        assertEq(token.balanceOf(address(checkout)), 0);
        assertTrue(checkout.isPaid(INV));
        InvoiceCheckout.Invoice memory inv = checkout.invoiceOf(INV);
        assertEq(inv.payer, payer);
        assertEq(inv.paidAt, uint64(block.timestamp));
    }

    function test_pay_revertsOnAmountTooLow() public {
        _create();
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.WrongAmount.selector, AMOUNT, AMOUNT - 1));
        checkout.pay(INV, AMOUNT - 1);
        vm.stopPrank();
    }

    function test_pay_revertsOnAmountTooHigh() public {
        _create();
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT + 1);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.WrongAmount.selector, AMOUNT, AMOUNT + 1));
        checkout.pay(INV, AMOUNT + 1);
        vm.stopPrank();
    }

    function test_pay_revertsOnSecondPayment() public {
        _create();
        vm.startPrank(payer);
        token.approve(address(checkout), 2 * AMOUNT);
        checkout.pay(INV, AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.AlreadyPaid.selector, INV));
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
    }

    function test_pay_revertsOnUnknownInvoice() public {
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.InvoiceNotFound.selector, INV));
        checkout.pay(INV, AMOUNT);
    }

    function test_pay_revertsAfterDeadline() public {
        _create();
        vm.warp(deadline + 1);
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.InvoiceExpired.selector, INV));
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
    }

    function test_pay_atExactDeadline_succeeds() public {
        _create();
        vm.warp(deadline);
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
        assertTrue(checkout.isPaid(INV));
    }

    // ---------- payWithAuthorization (EIP-3009) ----------

    function _signAuth(address from, uint256 key, uint256 value, bytes32 invoiceId)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        Signing.Auth memory a = Signing.Auth({
            from: from,
            to: address(checkout),
            value: value,
            validAfter: 0,
            validBefore: deadline,
            nonce: checkout.authorizationNonce(from, invoiceId)
        });
        return Signing.signReceive(vm, key, token.DOMAIN_SEPARATOR(), a);
    }

    function test_payWithAuthorization_relayerSubmits() public {
        _create();
        (uint8 v, bytes32 r, bytes32 s) = _signAuth(payer, payerKey, AMOUNT, INV);

        vm.prank(relayer);
        checkout.payWithAuthorization(INV, payer, AMOUNT, 0, deadline, v, r, s);

        assertEq(token.balanceOf(payee), AMOUNT);
        assertEq(token.balanceOf(payer), 1_000e6 - AMOUNT);
        assertTrue(checkout.isPaid(INV));
        assertTrue(token.authorizationState(payer, checkout.authorizationNonce(payer, INV)));
    }

    function test_payWithAuthorization_revertsOnWrongAmount() public {
        _create();
        (uint8 v, bytes32 r, bytes32 s) = _signAuth(payer, payerKey, AMOUNT - 1, INV);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.WrongAmount.selector, AMOUNT, AMOUNT - 1));
        checkout.payWithAuthorization(INV, payer, AMOUNT - 1, 0, deadline, v, r, s);
    }

    function test_payWithAuthorization_nonceBoundToPayer() public {
        _create();
        // Stranger signs for the same invoice: the nonce differs, and the payment is
        // recorded (and funded) by the stranger, never by `payer`.
        (, uint256 strangerKey) = makeAddrAndKey("stranger");
        assertTrue(checkout.authorizationNonce(payer, INV) != checkout.authorizationNonce(stranger, INV));
        (uint8 v, bytes32 r, bytes32 s) = _signAuth(stranger, strangerKey, AMOUNT, INV);
        vm.prank(relayer);
        checkout.payWithAuthorization(INV, stranger, AMOUNT, 0, deadline, v, r, s);
        assertEq(checkout.invoiceOf(INV).payer, stranger);
        assertEq(token.balanceOf(payer), 1_000e6);
    }

    function test_payWithAuthorization_revertsAfterDeadline() public {
        _create();
        (uint8 v, bytes32 r, bytes32 s) = _signAuth(payer, payerKey, AMOUNT, INV);
        vm.warp(deadline + 1);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.InvoiceExpired.selector, INV));
        checkout.payWithAuthorization(INV, payer, AMOUNT, 0, deadline, v, r, s);
    }

    // ---------- cancel ----------

    function test_cancel_byCreator_blocksPayment() public {
        _create();
        vm.prank(creator);
        vm.expectEmit(true, true, false, false, address(checkout));
        emit InvoiceCheckout.InvoiceCancelled(INV, creator);
        checkout.cancelInvoice(INV);

        assertEq(uint8(checkout.statusOf(INV)), uint8(InvoiceCheckout.Status.Cancelled));
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.InvoiceClosed.selector, INV));
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
    }

    function test_cancel_revertsForNonCreator() public {
        _create();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.NotCreator.selector, INV, stranger));
        checkout.cancelInvoice(INV);
    }

    function test_cancel_revertsAfterPaid() public {
        _create();
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.AlreadyPaid.selector, INV));
        checkout.cancelInvoice(INV);
    }

    // ---------- refund (expired invoice) ----------

    function test_refund_afterDeadline_byCreator() public {
        _create();
        vm.warp(deadline + 1);
        vm.prank(creator);
        vm.expectEmit(true, true, false, false, address(checkout));
        emit InvoiceCheckout.InvoiceRefunded(INV, creator);
        checkout.refundInvoice(INV);

        assertEq(uint8(checkout.statusOf(INV)), uint8(InvoiceCheckout.Status.Refunded));
        assertEq(token.balanceOf(payer), 1_000e6); // nothing was ever held
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.InvoiceClosed.selector, INV));
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
    }

    function test_refund_revertsBeforeDeadline() public {
        _create();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.DeadlineNotReached.selector, INV));
        checkout.refundInvoice(INV);
    }

    function test_refund_revertsForNonCreator() public {
        _create();
        vm.warp(deadline + 1);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.NotCreator.selector, INV, stranger));
        checkout.refundInvoice(INV);
    }

    function test_refund_revertsAfterPaid() public {
        _create();
        vm.startPrank(payer);
        token.approve(address(checkout), AMOUNT);
        checkout.pay(INV, AMOUNT);
        vm.stopPrank();
        vm.warp(deadline + 1);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(InvoiceCheckout.AlreadyPaid.selector, INV));
        checkout.refundInvoice(INV);
    }
}
