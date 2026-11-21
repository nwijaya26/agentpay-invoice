/**
 * AgentPay: an agent pays an InvoiceCheckout invoice, gasless, after checking the
 * guard rails a human owner would want checked first:
 *   1. The invoice is read from InvoiceCheckout (amount and payee are locked in on chain;
 *      the agent cannot change what it pays or to whom).
 *   2. Confirmation of Payee: the payee address on the invoice must match the address
 *      registered under PAYEE_NAME in PayeeRegistry, or the agent refuses to pay.
 *   3. If AGENT_WALLET_ADDRESS is set, its session must be active, the payee allowlisted
 *      and the remaining period budget sufficient — the same limits the wallet enforces
 *      on chain for wallet-funded payments.
 *   4. The agent signs an EIP-3009 ReceiveWithAuthorization (off-chain, free, no gas) and
 *      a RELAYER submits InvoiceCheckout.payWithAuthorization and pays the gas.
 *
 *   INVOICE_ID=0x… PAYEE_NAME=toko-berkah pnpm example pay-invoice-agent
 */
import { createWalletClient, formatUnits, http, isHex, parseAbi, parseSignature, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { aevumTestnet, authorizationWindow, checkoutTypedData, erc20Abi, txUrl } from "@aevum-kit/aevum";
import { connect, required, requiredAddress, requiredKey } from "./env";

const invoiceCheckoutAbi = parseAbi([
  "function invoiceOf(bytes32 invoiceId) view returns ((address creator, address payee, address token, uint256 amount, uint64 deadline, bytes32 ref, uint8 status, address payer, uint64 paidAt))",
  "function authorizationNonce(address payer, bytes32 invoiceId) view returns (bytes32)",
  "function payWithAuthorization(bytes32 invoiceId, address from, uint256 amount, uint256 validAfter, uint256 validBefore, uint8 v, bytes32 r, bytes32 s)",
]);
const payeeRegistryAbi = parseAbi([
  "function resolve(string name) view returns (address)",
  "function verify(string name, address expected) view returns (bool)",
]);
const agentWalletAbi = parseAbi([
  "function sessionActive() view returns (bool)",
  "function allowedPayee(address payee) view returns (bool)",
  "function remainingBudget() view returns (uint256)",
]);

const STATUS = ["None", "Open", "Paid", "Cancelled", "Refunded"];

function refuse(reason: string): never {
  console.error(`Agent refuses to pay: ${reason}`);
  process.exit(1);
}

const { client, chain, rpcUrl } = await connect();
const checkout = requiredAddress("INVOICE_CHECKOUT_ADDRESS");
const registry = requiredAddress("PAYEE_REGISTRY_ADDRESS");
const payeeName = required("PAYEE_NAME");
const invoiceIdRaw = required("INVOICE_ID");
if (!isHex(invoiceIdRaw) || invoiceIdRaw.length !== 66) refuse("INVOICE_ID must be a 32-byte hex string.");
const invoiceId = invoiceIdRaw as Hex;

const agent = privateKeyToAccount(requiredKey("AGENT_KEY"));
const relayer = createWalletClient({ account: privateKeyToAccount(requiredKey("RELAYER_KEY")), chain, transport: http(rpcUrl) });

// 1. Read the invoice. Amount, payee and deadline come from the contract, not from input.
const invoice = await client.readContract({ address: checkout, abi: invoiceCheckoutAbi, functionName: "invoiceOf", args: [invoiceId] });
if (invoice.status !== 1) refuse(`invoice is ${STATUS[invoice.status] ?? invoice.status}, not Open.`);
const nowSeconds = BigInt(Math.floor(Date.now() / 1000));
if (nowSeconds > invoice.deadline) refuse("invoice deadline has passed.");
const decimals = await client.readContract({ address: invoice.token, abi: erc20Abi, functionName: "decimals" });
console.log(`Invoice ${invoiceId}: ${formatUnits(invoice.amount, decimals)} to ${invoice.payee}, deadline ${new Date(Number(invoice.deadline) * 1000).toISOString()}`);

// 2. Confirmation of Payee: the name must resolve to the invoice's payee.
const registered = await client.readContract({ address: registry, abi: payeeRegistryAbi, functionName: "resolve", args: [payeeName] });
const confirmed = await client.readContract({ address: registry, abi: payeeRegistryAbi, functionName: "verify", args: [payeeName, invoice.payee] });
if (!confirmed) refuse(`"${payeeName}" is registered to ${registered}, not to the invoice payee ${invoice.payee}.`);
console.log(`Confirmation of Payee: "${payeeName}" -> ${registered} matches the invoice payee.`);

// 3. AgentWallet guard rails (when a wallet is configured for this agent).
if (process.env.AGENT_WALLET_ADDRESS) {
  const wallet = requiredAddress("AGENT_WALLET_ADDRESS");
  const active = await client.readContract({ address: wallet, abi: agentWalletAbi, functionName: "sessionActive" });
  if (!active) refuse("AgentWallet session is inactive, expired or revoked.");
  const allowed = await client.readContract({ address: wallet, abi: agentWalletAbi, functionName: "allowedPayee", args: [invoice.payee] });
  if (!allowed) refuse("payee is not on the AgentWallet allowlist.");
  const remaining = await client.readContract({ address: wallet, abi: agentWalletAbi, functionName: "remainingBudget" });
  if (remaining < invoice.amount) refuse(`remaining budget ${formatUnits(remaining, decimals)} is below the invoice amount.`);
  console.log(`AgentWallet checks passed (remaining budget ${formatUnits(remaining, decimals)}).`);
}

// 4. Agent signs EIP-3009; the nonce binds the signature to (agent, invoice).
const nonce = await client.readContract({ address: checkout, abi: invoiceCheckoutAbi, functionName: "authorizationNonce", args: [agent.address, invoiceId] });
const { validAfter, validBefore } = authorizationWindow(600);
const signature = await agent.signTypedData(
  checkoutTypedData(chain.id, invoice.token, { from: agent.address, to: checkout, value: invoice.amount, validAfter, validBefore, nonce }),
);
const { v, r, s, yParity } = parseSignature(signature);
console.log(`Agent ${agent.address} signed a gasless authorization for this invoice.`);

// 5. Relayer submits. Simulate first so a bad signature fails here, not on chain.
const call = {
  account: relayer.account,
  address: checkout,
  abi: invoiceCheckoutAbi,
  functionName: "payWithAuthorization",
  args: [invoiceId, agent.address, invoice.amount, validAfter, validBefore, v !== undefined ? Number(v) : 27 + (yParity ?? 0), r, s],
} as const;
await client.simulateContract(call);
const hash = await relayer.writeContract({ ...call, type: "legacy" });
const receipt = await client.waitForTransactionReceipt({ hash });

console.log(`Relayer ${relayer.account.address} submitted: ${receipt.status} in block ${receipt.blockNumber}`);
console.log(chain.id === aevumTestnet.id ? txUrl(hash) : `tx ${hash}`);
