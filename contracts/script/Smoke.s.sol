// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InvoiceCheckout} from "../src/InvoiceCheckout.sol";

/// @notice Post-deploy smoke test for InvoiceCheckout: create one invoice, pay it with
///   the exact amount, and require the invoice to end up Paid. Run it against the SAME
///   chain the deploy went to, with the addresses the deploy printed — nothing about the
///   deployment is hardcoded here.
///
///   Env:
///     INVOICE_CHECKOUT (required)  address printed by Deploy.s.sol
///     TOKEN            (optional)  defaults to the real tUSD8
///     PAYEE            (optional)  invoice payee; defaults to a burn address, so on a
///                                  fork the smoke money visibly leaves the payer
///     AMOUNT           (optional)  invoice amount in token base units; default 3e6 (3 tUSD8)
///     INVOICE_ID       (optional)  bytes32; default keccak256("agentpay-smoke").
///                                  Set a fresh one when re-running against the same deploy.
///
///   The broadcaster creates the invoice AND pays it, so it must hold at least AMOUNT of
///   TOKEN (on `make fork`: `make deal TO=<payer>` first) plus native gas.
///
///   make smoke-fork INVOICE_CHECKOUT=0x...    # wraps the fork plumbing, see Makefile
contract Smoke is Script {
    address constant AEVUM_TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;
    address constant DEFAULT_PAYEE = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        InvoiceCheckout checkout = InvoiceCheckout(vm.envAddress("INVOICE_CHECKOUT"));
        IERC20 token = IERC20(vm.envOr("TOKEN", AEVUM_TUSD8));
        address payee = vm.envOr("PAYEE", DEFAULT_PAYEE);
        uint256 amount = vm.envOr("AMOUNT", uint256(3e6));
        bytes32 invoiceId = vm.envOr("INVOICE_ID", keccak256("agentpay-smoke"));

        require(checkout.statusOf(invoiceId) == InvoiceCheckout.Status.None, "smoke: invoice id already used");

        vm.startBroadcast();
        (, address payer,) = vm.readCallers();
        checkout.createInvoice(invoiceId, payee, address(token), amount, uint64(block.timestamp + 1 days), bytes32("agentpay-smoke"));
        token.approve(address(checkout), amount);
        checkout.pay(invoiceId, amount);
        vm.stopBroadcast();

        InvoiceCheckout.Status status = checkout.statusOf(invoiceId);
        require(status == InvoiceCheckout.Status.Paid, "smoke: invoice is not Paid after paying the exact amount");

        console.log("chainId         ", block.chainid);
        console.log("InvoiceCheckout ", address(checkout));
        console.log("payer           ", payer);
        console.log("payee           ", payee);
        console.log("amount          ", amount);
        console.log("invoiceId       ", vm.toString(invoiceId));
        console.log("status          ", uint256(status), "(2 = Paid)");
    }
}
