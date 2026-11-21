// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InvoiceCheckout} from "../../src/InvoiceCheckout.sol";
import {AgentWallet} from "../../src/AgentWallet.sol";
import {PayeeRegistry} from "../../src/PayeeRegistry.sol";
import {Signing} from "../Signing.sol";

interface ITUSD8 is IERC20 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function authorizationState(address, bytes32) external view returns (bool);
}

/// @notice AgentPay contracts against the REAL tUSD8 on a local fork of Aevum testnet.
///         Funds come from `deal` (fork-only balance writes); nothing leaves this machine.
///         Run with: make test-fork
contract AgentPayForkTest is Test {
    ITUSD8 constant TUSD8 = ITUSD8(0x456569838f1d43009A91ebA4263147Afd7233483);

    address creator = makeAddr("creator");
    address payee = makeAddr("payee");
    address owner = makeAddr("owner");
    address agent = makeAddr("agent");

    bytes32 constant INV = keccak256("fork-invoice-1");
    bytes32 constant REF = keccak256("fork-ref-1");

    function _createInvoice(InvoiceCheckout checkout, uint256 amount) internal returns (bytes32) {
        vm.prank(creator);
        checkout.createInvoice(INV, payee, address(TUSD8), amount, uint64(block.timestamp + 1 days), REF);
        return INV;
    }

    function test_fork_invoicePay_realTusd8() public {
        (address payer,) = makeAddrAndKey("payer");
        InvoiceCheckout checkout = new InvoiceCheckout();
        _createInvoice(checkout, 7e6);
        deal(address(TUSD8), payer, 20e6);

        vm.startPrank(payer);
        TUSD8.approve(address(checkout), 7e6);
        checkout.pay(INV, 7e6);
        vm.stopPrank();

        assertEq(TUSD8.balanceOf(payee), 7e6);
        assertEq(TUSD8.balanceOf(payer), 13e6);
        assertTrue(checkout.isPaid(INV));
    }

    function test_fork_invoicePayWithAuthorization_realTusd8() public {
        (address payer, uint256 payerKey) = makeAddrAndKey("payer");
        InvoiceCheckout checkout = new InvoiceCheckout();
        _createInvoice(checkout, 5e6);
        deal(address(TUSD8), payer, 20e6);

        uint256 validBefore = block.timestamp + 1 hours;
        Signing.Auth memory a = Signing.Auth({
            from: payer,
            to: address(checkout),
            value: 5e6,
            validAfter: 0,
            validBefore: validBefore,
            nonce: checkout.authorizationNonce(payer, INV)
        });
        (uint8 v, bytes32 r, bytes32 s) = Signing.signReceive(vm, payerKey, TUSD8.DOMAIN_SEPARATOR(), a);

        vm.prank(makeAddr("relayer"));
        checkout.payWithAuthorization(INV, payer, 5e6, 0, validBefore, v, r, s);

        assertEq(TUSD8.balanceOf(payee), 5e6);
        assertEq(TUSD8.balanceOf(payer), 15e6);
        assertTrue(TUSD8.authorizationState(payer, checkout.authorizationNonce(payer, INV)));
    }

    function test_fork_agentWalletPaysInvoice_realTusd8() public {
        InvoiceCheckout checkout = new InvoiceCheckout();
        PayeeRegistry registry = new PayeeRegistry();
        AgentWallet wallet = new AgentWallet(IERC20(address(TUSD8)), owner);
        _createInvoice(checkout, 9e6);
        deal(address(TUSD8), owner, 100e6);

        // Confirmation-of-Payee: the payee registers their name; the agent side checks it.
        vm.prank(payee);
        registry.register("fork-payee", payee);
        assertTrue(registry.verify("fork-payee", checkout.invoiceOf(INV).payee));

        vm.startPrank(owner);
        wallet.configureSession(agent, 50e6, 1 days, uint64(block.timestamp + 7 days));
        wallet.setPayeeAllowed(payee, true);
        TUSD8.approve(address(wallet), 100e6);
        wallet.fund(100e6);
        vm.stopPrank();

        vm.prank(agent);
        wallet.payInvoice(checkout, INV);

        assertTrue(checkout.isPaid(INV));
        assertEq(TUSD8.balanceOf(payee), 9e6);
        assertEq(wallet.spentInPeriod(), 9e6);
        assertEq(wallet.remainingBudget(), 41e6);
    }

    function test_fork_agentWalletOverBudgetReverts_realTusd8() public {
        InvoiceCheckout checkout = new InvoiceCheckout();
        AgentWallet wallet = new AgentWallet(IERC20(address(TUSD8)), owner);
        _createInvoice(checkout, 60e6); // above the 50 tUSD8 cap below
        deal(address(TUSD8), owner, 100e6);

        vm.startPrank(owner);
        wallet.configureSession(agent, 50e6, 1 days, uint64(block.timestamp + 7 days));
        wallet.setPayeeAllowed(payee, true);
        TUSD8.approve(address(wallet), 100e6);
        wallet.fund(100e6);
        vm.stopPrank();

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentWallet.BudgetExceeded.selector, 50e6, 60e6));
        wallet.payInvoice(checkout, INV);
        assertFalse(checkout.isPaid(INV));
    }
}
