// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Checkout} from "../src/Checkout.sol";
import {InvoiceCheckout} from "../src/InvoiceCheckout.sol";
import {PayeeRegistry} from "../src/PayeeRegistry.sol";
import {AgentWallet} from "../src/AgentWallet.sol";
import {MockUSD8} from "../src/mocks/MockUSD8.sol";

/// @notice Deploys Checkout plus the AgentPay contracts: InvoiceCheckout, PayeeRegistry
///   and AgentWallet.
///   - Aevum testnet and `make fork`: uses the real tUSD8.
///   - `make anvil` (chain 31337) only: deploys MockUSD8 first and mints 1,000 to the deployer.
///   - Anywhere else it stops, rather than deploy a token anyone can mint.
///   MERCHANT (optional env) receives Checkout payments; defaults to the deployer. anvil's
///   public accounts are refused as merchant outside local chains: anyone could take that money.
///   OWNER (optional env) owns the AgentWallet; defaults to the deployer.
///
///   The three AgentPay contracts do not reference each other, so deploy order between
///   them does not matter; AgentWallet only needs the token address, known up front.
///
///   Dry run (simulate, deploy nothing): drop `--broadcast` from any deploy command.
///
///   make deploy-local                         # anvil on 127.0.0.1:8545
///   make deploy-fork                          # local fork of Aevum (see Makefile)
///   make deploy-aevum ACCOUNT=deployer        # uses a keystore made with `cast wallet import`
contract Deploy is Script {
    address constant AEVUM_TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;
    uint256 constant ANVIL_CHAIN = 31337;
    uint256 constant FORK_CHAIN = 440050;
    /// anvil's default accounts come from this public mnemonic.
    string constant ANVIL_MNEMONIC = "test test test test test test test test test test test junk";

    function run()
        external
        returns (
            Checkout checkout,
            address token,
            InvoiceCheckout invoiceCheckout,
            PayeeRegistry payeeRegistry,
            AgentWallet agentWallet
        )
    {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address merchant = vm.envOr("MERCHANT", deployer);
        address owner = vm.envOr("OWNER", deployer);
        bool local = block.chainid == ANVIL_CHAIN || block.chainid == FORK_CHAIN;
        require(local || !isAnvilAccount(merchant), "MERCHANT is a public anvil account. Use your own address.");

        if (AEVUM_TUSD8.code.length > 0) {
            token = AEVUM_TUSD8;
        } else {
            require(block.chainid == ANVIL_CHAIN, "tUSD8 not found on this chain. Check the RPC (Aevum testnet is 44005).");
            MockUSD8 mock = new MockUSD8();
            mock.mint(deployer, 1_000e6);
            token = address(mock);
        }
        checkout = new Checkout(IERC20(token), merchant);
        invoiceCheckout = new InvoiceCheckout();
        payeeRegistry = new PayeeRegistry();
        agentWallet = new AgentWallet(IERC20(token), owner);
        vm.stopBroadcast();

        console.log("chainId         ", block.chainid);
        console.log("token           ", token);
        console.log("merchant        ", merchant);
        console.log("Checkout        ", address(checkout));
        console.log("InvoiceCheckout ", address(invoiceCheckout));
        console.log("PayeeRegistry   ", address(payeeRegistry));
        console.log("AgentWallet     ", address(agentWallet));
        console.log("AgentWalletOwner", owner);
    }

    function isAnvilAccount(address a) internal pure returns (bool) {
        for (uint32 i = 0; i < 10; i++) {
            if (vm.addr(vm.deriveKey(ANVIL_MNEMONIC, i)) == a) return true;
        }
        return false;
    }
}
