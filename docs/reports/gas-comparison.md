# Gas Optimization Report: RWA T-Bill Tokenization Platform

<div class="document-meta">
<strong>Scope:</strong> Gas-sensitive protocol operations and required L1 vs L2 comparison table<br>
<strong>Tooling:</strong> Foundry gas snapshots through `script/GasCompare.s.sol`<br>
<strong>Local chain:</strong> Anvil chain ID 31337<br>
<strong>L2 target:</strong> Base Sepolia<br>
<strong>Status:</strong> Local gas measured. L1 and Base Sepolia columns are filled after real RPC deployment secrets are provided.
</div>

## 1. Executive Summary

The protocol keeps gas-sensitive logic concentrated in four areas: asset minting, ERC4626 vault accounting, AMM liquidity and swap math, and oracle reads. The largest local cost is AMM liquidity addition because it includes two token transfers, reserve updates, LP share minting, and first-liquidity square-root calculation.

<div class="metric-grid">
<div class="metric"><strong>17,308</strong><span>Local gas for `swapExactIn` in the benchmark path.</span></div>
<div class="metric"><strong>2,736</strong><span>Local gas for adapter `latestPrice` validation.</span></div>
<div class="metric"><strong>152,599</strong><span>Local gas for full AMM add-liquidity path.</span></div>
</div>

## 2. Measurement Method

The gas numbers are produced by `script/GasCompare.s.sol` against a deployed local protocol. The script performs representative operations rather than isolated opcode microbenchmarks, so each number includes realistic protocol overhead such as role checks, ERC20 accounting, SafeERC20 calls, reserve synchronization, and event emission where applicable.

Recommended commands:

```bash
npm run anvil
npm run deploy:anvil
forge script script/GasCompare.s.sol:GasCompare --rpc-url http://127.0.0.1:8545
```

For real comparison, run the same script against Ethereum Sepolia or a mainnet fork for L1-style gas and against Base Sepolia for L2 deployment gas.

## 3. Required L1 vs L2 Comparison Table

| Operation             | Local Anvil gas | L1 measured | Base Sepolia measured | Notes                                                                               |
| --------------------- | --------------: | ----------: | --------------------: | ----------------------------------------------------------------------------------- |
| TBill mint            |          26,003 |         TBD |                   TBD | Role-gated ERC20 mint by authorized issuer.                                         |
| Vault deposit         |          79,670 |         TBD |                   TBD | ERC4626 share mint plus SafeERC20 transfer.                                         |
| Vault reportYield     |           7,519 |         TBD |                   TBD | Role-gated yield transfer into the vault.                                           |
| AMM addLiquidity      |         152,599 |         TBD |                   TBD | Two token transfers, LP minting, reserve sync, and initial square-root calculation. |
| AMM swapExactIn       |          17,308 |         TBD |                   TBD | Fee math, slippage check, output transfer, and invariant check.                     |
| Oracle latestPrice    |           2,736 |         TBD |                   TBD | Feed read plus stale, zero, and negative answer validation.                         |
| Treasury depositToken |          28,994 |         TBD |                   TBD | Pull-payment accounting and SafeERC20 transfer.                                     |

## 4. Optimization Decisions

| Decision                             | Before / alternative                  | After / implementation                       | Reason                                                                                |
| ------------------------------------ | ------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------- |
| Inline Yul square root               | Pure Solidity Babylonian helper       | `RwaMath.sqrtYul` for AMM initial liquidity  | Satisfies assembly requirement and keeps the hot calculation compact.                 |
| Pull-payment treasury                | Push transfer during scheduling       | Schedule owed balance, payee withdraws later | Avoids failed payout loops and makes external call surface smaller.                   |
| Non-upgradeable supporting contracts | Proxy every contract                  | Only `TBillToken` is UUPS upgradeable        | Reduces deploy and runtime complexity for AMM, vault, oracle, treasury, and governor. |
| Immutable AMM token addresses        | Storage reads for token addresses     | Constructor immutables                       | Avoids repeated storage reads in swap and liquidity paths.                            |
| Adapter-level oracle validation      | Duplicate validation in each consumer | Centralized `OracleAdapter` checks           | Keeps feed safety logic reusable and auditable.                                       |

## 5. Yul vs Solidity Benchmark Context

`RwaMath.sol` contains both `sqrtSolidity` and `sqrtYul`. The production AMM path uses the Yul helper only during first-liquidity LP minting. Keeping the assembly block small is intentional: it demonstrates the advanced Solidity requirement without hiding broad protocol logic inside assembly.

Security note: the Yul helper is deterministic, does not perform external calls, and is covered by tests comparing behavior against the pure Solidity equivalent.

## 6. Final Submission Steps

Before final submission, fill the L1 and Base Sepolia columns by running the same benchmark script against real RPC endpoints:

```bash
forge script script/GasCompare.s.sol:GasCompare --rpc-url "$SEPOLIA_RPC_URL"
forge script script/GasCompare.s.sol:GasCompare --rpc-url "$BASE_SEPOLIA_RPC_URL"
```

Then update this report with transaction hashes or script output references. The current local report is complete for Anvil and ready to be extended once deployment secrets are available.


### Base Sepolia Verification Notes

Deployment verification is performed through Basescan after broadcasting contracts with Foundry scripts.

The final report will include:
- deployed contract addresses
- Basescan verification links
- subgraph deployment reference
- benchmark transaction references