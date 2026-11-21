// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InvoiceCheckout} from "./InvoiceCheckout.sol";

/// @title AgentWallet
/// @notice A spending wallet for an autonomous agent, with the controls a human owner
///         needs before letting software move money: a budget cap per period, a session
///         expiry, a payee allowlist, and instant revocation. The agent can only pay
///         allowlisted payees, only up to the remaining period budget, and only until
///         the session expires or the owner revokes it — every violation reverts with a
///         specific error. The owner funds and drains the wallet and sets the policy;
///         the agent can do nothing else.
contract AgentWallet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    address public agent;
    uint256 public budgetCap;
    uint64 public periodLength;
    uint64 public periodStart;
    uint256 public spentInPeriod;
    uint64 public expiresAt;
    bool public revoked;

    mapping(address payee => bool allowed) public allowedPayee;

    event SessionConfigured(address indexed agent, uint256 budgetCap, uint64 periodLength, uint64 expiresAt);
    event SessionRevoked(address indexed agent);
    event PayeeAllowlistUpdated(address indexed payee, bool allowed);
    event Funded(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event AgentPaid(address indexed agent, address indexed to, uint256 amount, uint256 spentInPeriod);
    event AgentPaidInvoice(
        address indexed agent, bytes32 indexed invoiceId, address indexed payee, uint256 amount
    );

    error NoSession();
    error NotAgent(address caller);
    error SessionRevokedError();
    error SessionExpired(uint64 expiresAt);
    error PayeeNotAllowed(address payee);
    error BudgetExceeded(uint256 remaining, uint256 amount);
    error InvoiceNotOpen(bytes32 invoiceId);
    error TokenMismatch(address invoiceToken);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidPolicy();

    constructor(IERC20 token_, address owner_) Ownable(owner_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    // ---------- owner: policy ----------

    /// @notice (Re)configure the agent session. Resets the period budget and clears any
    ///         revocation. The owner stays in control: a new session is a new grant.
    function configureSession(address agent_, uint256 budgetCap_, uint64 periodLength_, uint64 expiresAt_)
        external
        onlyOwner
    {
        if (agent_ == address(0)) revert ZeroAddress();
        if (budgetCap_ == 0 || periodLength_ == 0 || expiresAt_ <= block.timestamp) revert InvalidPolicy();
        agent = agent_;
        budgetCap = budgetCap_;
        periodLength = periodLength_;
        expiresAt = expiresAt_;
        periodStart = uint64(block.timestamp);
        spentInPeriod = 0;
        revoked = false;
        emit SessionConfigured(agent_, budgetCap_, periodLength_, expiresAt_);
    }

    /// @notice Allow or disallow a payee. The agent can pay nobody else.
    function setPayeeAllowed(address payee, bool allowed) external onlyOwner {
        if (payee == address(0)) revert ZeroAddress();
        allowedPayee[payee] = allowed;
        emit PayeeAllowlistUpdated(payee, allowed);
    }

    /// @notice Revoke the session instantly. The agent cannot pay again until the owner
    ///         configures a new session.
    function revoke() external onlyOwner {
        revoked = true;
        emit SessionRevoked(agent);
    }

    // ---------- owner: funds ----------

    /// @notice Pull `amount` of the wallet token from the owner into this wallet.
    function fund(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    /// @notice Take `amount` of the wallet token back out. Owner only.
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        token.safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    // ---------- agent: spending ----------

    /// @notice Pay an allowlisted address directly, within the session budget.
    function pay(address to, uint256 amount) external {
        _spend(to, amount);
        token.safeTransfer(to, amount);
        emit AgentPaid(msg.sender, to, amount, spentInPeriod);
    }

    /// @notice Pay an InvoiceCheckout invoice from this wallet. The invoice's payee must
    ///         be allowlisted and the invoice amount must fit the remaining budget; the
    ///         wallet approves the checkout for exactly the invoice amount.
    function payInvoice(InvoiceCheckout checkout, bytes32 invoiceId) external {
        InvoiceCheckout.Invoice memory inv = checkout.invoiceOf(invoiceId);
        if (inv.status != InvoiceCheckout.Status.Open) revert InvoiceNotOpen(invoiceId);
        if (inv.token != address(token)) revert TokenMismatch(inv.token);
        _spend(inv.payee, inv.amount);
        token.forceApprove(address(checkout), inv.amount);
        checkout.pay(invoiceId, inv.amount);
        emit AgentPaidInvoice(msg.sender, invoiceId, inv.payee, inv.amount);
    }

    // ---------- views ----------

    /// @notice Budget left in the current period (accounts for period rollover).
    function remainingBudget() public view returns (uint256) {
        if (agent == address(0)) return 0;
        if (block.timestamp >= uint256(periodStart) + periodLength) return budgetCap;
        return budgetCap - spentInPeriod;
    }

    /// @notice True if the agent could pay right now (session set, not revoked, not expired).
    function sessionActive() public view returns (bool) {
        return agent != address(0) && !revoked && block.timestamp <= expiresAt;
    }

    // ---------- internals ----------

    function _spend(address to, uint256 amount) private {
        if (agent == address(0)) revert NoSession();
        if (msg.sender != agent) revert NotAgent(msg.sender);
        if (revoked) revert SessionRevokedError();
        if (block.timestamp > expiresAt) revert SessionExpired(expiresAt);
        if (amount == 0) revert ZeroAmount();
        if (!allowedPayee[to]) revert PayeeNotAllowed(to);
        if (block.timestamp >= uint256(periodStart) + periodLength) {
            periodStart = uint64(block.timestamp);
            spentInPeriod = 0;
        }
        uint256 remaining = budgetCap - spentInPeriod;
        if (amount > remaining) revert BudgetExceeded(remaining, amount);
        spentInPeriod += amount;
    }
}
