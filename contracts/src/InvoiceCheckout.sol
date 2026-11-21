// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice EIP-3009 (USDC-style) signed transfers. tUSD8 on Aevum implements this.
/// @dev Same interface as the starter kit's Checkout.sol.
interface IERC3009 {
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @title InvoiceCheckout
/// @notice Invoice payments with the amount LOCKED IN at creation time. Unlike a plain
///         checkout, the payer cannot choose what to pay: `pay` and `payWithAuthorization`
///         revert unless the amount matches the invoice exactly, and the EIP-3009 nonce is
///         bound to (payer, invoiceId) so a signature cannot be replayed for another payer
///         or another invoice. The money goes straight to the payee; nothing is escrowed,
///         and the `Paid` event is the on-chain receipt.
/// @dev Derived from the Aevum Starter Kit's Checkout.sol (MIT, PQA Labs) and extended
///      with invoices, deadlines, cancel/refund and per-invoice tokens.
contract InvoiceCheckout {
    using SafeERC20 for IERC20;

    enum Status {
        None,
        Open,
        Paid,
        Cancelled,
        Refunded
    }

    struct Invoice {
        address creator;
        address payee;
        address token;
        uint256 amount;
        uint64 deadline;
        bytes32 ref;
        Status status;
        address payer;
        uint64 paidAt;
    }

    mapping(bytes32 invoiceId => Invoice) private _invoices;

    event InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed creator,
        address indexed payee,
        address token,
        uint256 amount,
        uint64 deadline,
        bytes32 ref
    );
    event Paid(bytes32 indexed invoiceId, address indexed payer, address indexed payee, uint256 amount);
    event InvoiceCancelled(bytes32 indexed invoiceId, address indexed creator);
    event InvoiceRefunded(bytes32 indexed invoiceId, address indexed creator);

    error InvoiceExists(bytes32 invoiceId);
    error InvoiceNotFound(bytes32 invoiceId);
    error NotCreator(bytes32 invoiceId, address caller);
    error AlreadyPaid(bytes32 invoiceId);
    error InvoiceClosed(bytes32 invoiceId);
    error InvoiceExpired(bytes32 invoiceId);
    error WrongAmount(uint256 expected, uint256 actual);
    error DeadlineNotReached(bytes32 invoiceId);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidDeadline();

    /// @notice Create an invoice. `invoiceId` is chosen by the creator (e.g. a hash of the
    ///         invoice number) and can only be used once. `ref` is a free-form external
    ///         reference (order number, memo hash, ...) stored with the invoice.
    function createInvoice(
        bytes32 invoiceId,
        address payee,
        address token,
        uint256 amount,
        uint64 deadline,
        bytes32 ref
    ) external {
        if (payee == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (_invoices[invoiceId].status != Status.None) revert InvoiceExists(invoiceId);

        _invoices[invoiceId] = Invoice({
            creator: msg.sender,
            payee: payee,
            token: token,
            amount: amount,
            deadline: deadline,
            ref: ref,
            status: Status.Open,
            payer: address(0),
            paidAt: 0
        });
        emit InvoiceCreated(invoiceId, msg.sender, payee, token, amount, deadline, ref);
    }

    /// @notice Pay `invoiceId` with tokens you have approved to this contract.
    ///         Reverts unless `amount` equals the invoice amount exactly.
    function pay(bytes32 invoiceId, uint256 amount) external {
        _checkPayable(invoiceId, amount);
        _recordPayment(invoiceId, msg.sender);
        Invoice storage inv = _invoices[invoiceId];
        IERC20(inv.token).safeTransferFrom(msg.sender, inv.payee, amount);
    }

    /// @notice Pay `invoiceId` with an EIP-3009 `ReceiveWithAuthorization` signed by `from`.
    ///         Anyone (a relayer, an agent) can submit it; `from` needs no native gas.
    ///         The signed nonce must be `authorizationNonce(from, invoiceId)` and `to` in
    ///         the signed message must be this contract.
    function payWithAuthorization(
        bytes32 invoiceId,
        address from,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _checkPayable(invoiceId, amount);
        _recordPayment(invoiceId, from);
        bytes32 nonce = authorizationNonce(from, invoiceId);
        address token = _invoices[invoiceId].token;
        _receiveAuthorization(token, from, amount, validAfter, validBefore, nonce, v, r, s);
        IERC20(token).safeTransfer(_invoices[invoiceId].payee, amount);
    }

    function _receiveAuthorization(
        address token,
        address from,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        IERC3009(token)
            .receiveWithAuthorization(from, address(this), amount, validAfter, validBefore, nonce, v, r, s);
    }

    /// @notice Cancel an unpaid invoice. Only the creator, only while it is open.
    ///         A cancelled invoice can never be paid.
    function cancelInvoice(bytes32 invoiceId) external {
        Invoice storage inv = _checkCreatorOpen(invoiceId);
        inv.status = Status.Cancelled;
        emit InvoiceCancelled(invoiceId, msg.sender);
    }

    /// @notice Void an invoice whose deadline passed unpaid ("refund" of an expired
    ///         invoice). Only the creator, only after the deadline. No tokens move:
    ///         payments are never escrowed here, so there is nothing held to send back;
    ///         this formally closes the expired invoice so it can no longer be paid.
    function refundInvoice(bytes32 invoiceId) external {
        Invoice storage inv = _checkCreatorOpen(invoiceId);
        if (block.timestamp <= inv.deadline) revert DeadlineNotReached(invoiceId);
        inv.status = Status.Refunded;
        emit InvoiceRefunded(invoiceId, msg.sender);
    }

    /// @notice The EIP-3009 nonce `payer` must sign to pay `invoiceId` through this contract.
    function authorizationNonce(address payer, bytes32 invoiceId) public pure returns (bytes32) {
        return keccak256(abi.encode(payer, invoiceId));
    }

    function invoiceOf(bytes32 invoiceId) external view returns (Invoice memory) {
        return _invoices[invoiceId];
    }

    function isPaid(bytes32 invoiceId) external view returns (bool) {
        return _invoices[invoiceId].status == Status.Paid;
    }

    function statusOf(bytes32 invoiceId) external view returns (Status) {
        return _invoices[invoiceId].status;
    }

    function _checkPayable(bytes32 invoiceId, uint256 amount) private view {
        Invoice storage inv = _invoices[invoiceId];
        if (inv.status == Status.None) revert InvoiceNotFound(invoiceId);
        if (inv.status == Status.Paid) revert AlreadyPaid(invoiceId);
        if (inv.status != Status.Open) revert InvoiceClosed(invoiceId);
        if (block.timestamp > inv.deadline) revert InvoiceExpired(invoiceId);
        if (amount != inv.amount) revert WrongAmount(inv.amount, amount);
    }

    function _checkCreatorOpen(bytes32 invoiceId) private view returns (Invoice storage inv) {
        inv = _invoices[invoiceId];
        if (inv.status == Status.None) revert InvoiceNotFound(invoiceId);
        if (msg.sender != inv.creator) revert NotCreator(invoiceId, msg.sender);
        if (inv.status == Status.Paid) revert AlreadyPaid(invoiceId);
        if (inv.status != Status.Open) revert InvoiceClosed(invoiceId);
    }

    function _recordPayment(bytes32 invoiceId, address payer) private {
        Invoice storage inv = _invoices[invoiceId];
        inv.status = Status.Paid;
        inv.payer = payer;
        inv.paidAt = uint64(block.timestamp);
        emit Paid(invoiceId, payer, inv.payee, inv.amount);
    }
}
