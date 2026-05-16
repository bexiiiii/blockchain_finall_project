# Architecture & Design Document: RWA T-Bill Tokenization Platform

<div class="document-meta">
<strong>Course:</strong> Blockchain Technologies 2, Final Project<br>
<strong>Scenario:</strong> Option C - RWA Tokenization Platform<br>
<strong>Protocol:</strong> Tokenized short-duration U.S. T-Bill reserve model<br>
<strong>Target network:</strong> Base Sepolia, with Anvil for local demos<br>
<strong>Tooling:</strong> Foundry, Anvil, OpenZeppelin 5.6.1, Vite React, Wagmi, Viem, RainbowKit, The Graph<br>
<strong>Team ownership:</strong> Tokhtamishov Bekhruz - contracts, security, tests, deploy. Zhangir Muslimov - frontend, subgraph, docs, presentation, gas report.
</div>

## 1. Executive Architecture Summary

The system implements a full-stack RWA protocol around a simplified tokenized T-Bill product. Authorized issuers mint `TBILL` only after off-chain reserve evidence exists. Investors can hold `TBILL`, deposit it into an ERC4626 vault, provide liquidity against a settlement token in a from-scratch AMM, and govern privileged protocol changes through OpenZeppelin Governor plus a two-day Timelock.

<div class="metric-grid">
<div class="metric"><strong>10</strong><span>Production contracts across tokenization, DeFi, oracle, governance, treasury, and deployment infrastructure.</span></div>
<div class="metric"><strong>88</strong><span>Foundry tests covering unit, fuzz, invariant, fork hooks, and vulnerability case studies.</span></div>
<div class="metric"><strong>92.31%</strong><span>Line coverage for production <code>src/</code> contracts with mocks, scripts, and tests excluded.</span></div>
</div>

### Mandatory Requirement Coverage

| Requirement area  | Implementation                                                                                                                                           |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Advanced Solidity | UUPS `TBillToken`, V1 to V2 upgrade path, `ProtocolFactory` with CREATE and CREATE2, inline Yul math benchmarked against Solidity.                       |
| Token standards   | `RwaGovernanceToken` as ERC20Votes + ERC20Permit, `ReserveCertificateNFT` as ERC721, `TBillVault` as ERC4626.                                            |
| DeFi primitive    | `RwaStableAMM`, built from scratch as constant product x\*y=k with 0.3% fee, slippage checks, deadlines, and LP accounting.                              |
| Oracles           | `OracleAdapter` reads Chainlink-compatible price and reserve feeds with stale, zero, and negative answer reverts.                                        |
| Indexing          | The Graph subgraph indexes assets, transfers, vault actions, swaps, liquidity, proposals, votes, and treasury payments.                                  |
| Governance        | OpenZeppelin Governor, timestamp clock, 1 day voting delay, 1 week voting period, 4% quorum, 1% proposal threshold, and 2 day Timelock.                  |
| Layer 2           | Deployment scripts target Base Sepolia and write deterministic deployment manifests. Anvil is used for reproducible local verification.                  |
| Frontend          | Vite React dApp supports wallet connection, network detection, protocol reads, state-changing writes, governance voting, and subgraph activity sections. |
| DevOps            | CI runs compile, test, coverage, formatting, Solhint, Slither, frontend build, and a no-Hardhat guard.                                                   |

## 2. System Context Diagram

<div class="diagram">
<div class="diagram-title">C4 Level 1 - protocol in context</div>
<div class="flow-row">
<div class="step">Investor<small>Connects wallet, holds TBILL, deposits to vault, swaps, votes.</small></div>
<div class="step">Wallet<small>MetaMask or WalletConnect signs reads and transactions.</small></div>
<div class="step">RWA Protocol<small>Solidity contracts on Base Sepolia or Anvil.</small></div>
<div class="step">External Data<small>Chainlink-compatible price and reserve feeds.</small></div>
<div class="step">Indexing/UI<small>The Graph feeds the activity and governance views.</small></div>
</div>
</div>

The protocol boundary is the deployed contract set plus the subgraph schema. The legal custody of the real-world T-Bill reserve remains an off-chain assumption. On testnet, the reserve feed is intentionally mock-backed because no official Base Sepolia T-Bill proof-of-reserve feed is assumed.

### External Actors and Responsibilities

| Actor / system             | Responsibility                                                                     | Trust level                                                            |
| -------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Investor                   | Uses wallet, deposits, swaps, delegates, votes, and monitors proposals.            | Does not need privileged roles.                                        |
| Authorized issuer          | Mints `TBILL` only after reserve evidence exists.                                  | Trusted operational actor, removable by governance.                    |
| Governor voters            | Approve or reject parameter changes, role changes, treasury actions, and upgrades. | Token-weighted governance with checkpointed voting power.              |
| Timelock                   | Executes successful governance actions after a two-day delay.                      | Root admin after deployment.                                           |
| Chainlink-compatible feeds | Provide latest price and reserve answers.                                          | Trusted for correctness and freshness within configured max staleness. |
| The Graph                  | Indexes events for the frontend and demo queries.                                  | Read-only convenience layer; contract state is source of truth.        |

## 3. Container and Component Architecture

<div class="diagram">
<div class="diagram-title">Contract topology and data flow</div>
<div class="flow-row">
<div class="step">Frontend<small>RainbowKit, Wagmi, Viem, transaction UX, error messages.</small></div>
<div class="step">Protocol Reads/Writes<small>TBILL, vault, AMM, governor, oracle, treasury.</small></div>
<div class="step">Governance Core<small>ERC20Votes token, Governor, TimelockController.</small></div>
<div class="step">Admin Targets<small>Token roles, vault pause/yield, oracle feeds, treasury.</small></div>
<div class="step">Indexing<small>Events mapped into GraphQL entities for activity pages.</small></div>
</div>
</div>

### Contract Map

| Contract                | Pattern / standard              | Primary responsibility                                                                                                    |
| ----------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `TBillToken`            | ERC20, UUPS, AccessControl      | Asset-backed token minted by authorized issuers. Supports pause, burn, registry updates, and Timelock-controlled upgrade. |
| `TBillTokenV2`          | UUPS upgrade target             | Appends `complianceUri` after V1 storage and proves upgrade path without storage collision.                               |
| `RwaGovernanceToken`    | ERC20Votes, ERC20Permit         | Governance voting power, delegation, permit-based approvals, timestamp-based ERC6372 clock.                               |
| `ReserveCertificateNFT` | ERC721, AccessControl, Pausable | Issues reserve evidence certificates with metadata URIs for off-chain collateral documentation.                           |
| `TBillVault`            | ERC4626, ReentrancyGuard        | Tokenized vault for TBILL deposits and role-gated yield reporting.                                                        |
| `RwaStableAMM`          | Custom AMM, ERC20 LP            | Constant-product liquidity pool with 0.3% fee, slippage protection, deadlines, and LP share accounting.                   |
| `OracleAdapter`         | Adapter / interface abstraction | Wraps Chainlink-compatible price and reserve feeds, enforcing max staleness and answer validity.                          |
| `ProtocolTreasury`      | Pull payments                   | Holds ETH/ERC20 treasury assets and lets payees withdraw scheduled payments.                                              |
| `ProtocolFactory`       | Factory, CREATE, CREATE2        | Deploys new UUPS asset proxies through both normal and deterministic deployment paths.                                    |
| `RwaGovernor`           | Governor + Timelock             | Proposal lifecycle: propose, vote, queue, execute.                                                                        |

### Proxy Layout and Admin Boundary

Only `TBillToken` is upgradeable. The proxy address is the user-facing asset contract. The implementation contract disables initializers in its constructor, and the proxy is initialized exactly once through `ERC1967Proxy` constructor calldata. The `UPGRADER_ROLE` is handed to the Timelock, so upgrades require a successful governance proposal and a two-day delay.

## 4. Critical User Flow 1 - Issuer Mint

<div class="diagram">
<div class="diagram-title">Issuer-backed mint flow</div>
<div class="flow-row">
<div class="step">Reserve evidence<small>Issuer prepares off-chain T-Bill custody documentation.</small></div>
<div class="step">Certificate NFT<small>Issuer mints an ERC721 certificate URI for audit trail.</small></div>
<div class="step">Oracle check<small>Frontend and scripts can read reserve feed freshness.</small></div>
<div class="step">Mint TBILL<small>`mint(to, amount)` requires `ISSUER_ROLE`.</small></div>
<div class="step">Index events<small>Transfers and certificates become GraphQL activity.</small></div>
</div>
</div>

Security properties:

- Minting is role-gated through OpenZeppelin `AccessControl`.
- Governance can remove compromised issuers without upgrading the token.
- The ERC20 transfer event is indexed by the subgraph for off-chain reconciliation.
- The production design expects real reserve feeds before mainnet; the testnet path documents mock feeds explicitly.

## 5. Critical User Flow 2 - ERC4626 Deposit and Yield

<div class="diagram">
<div class="diagram-title">Vault lifecycle</div>
<div class="flow-row">
<div class="step">Approve<small>User approves `TBillVault` to move TBILL.</small></div>
<div class="step">Deposit<small>Vault receives assets through SafeERC20 and mints shares.</small></div>
<div class="step">Accrue yield<small>Role-gated manager reports yield by transferring extra TBILL.</small></div>
<div class="step">Withdraw<small>User burns shares and receives assets under ERC4626 rounding.</small></div>
<div class="step">Index<small>Deposits, withdrawals, and yield reports are subgraph entities.</small></div>
</div>
</div>

The vault uses OpenZeppelin ERC4626 conversion logic and the tests include rounding-focused fuzz cases. All externally callable value-moving vault functions are `nonReentrant`, use SafeERC20, and can be paused for incident response.

## 6. Critical User Flow 3 - Governance Lifecycle

<div class="diagram">
<div class="diagram-title">Proposal to execution</div>
<div class="flow-row">
<div class="step">Delegate<small>Holder checkpoints voting power through `delegate`.</small></div>
<div class="step">Propose<small>Proposer must meet 1% proposal threshold.</small></div>
<div class="step">Vote<small>Voting opens after 1 day and lasts 1 week.</small></div>
<div class="step">Queue<small>Successful proposal schedules Timelock operation.</small></div>
<div class="step">Execute<small>After 2 days, Governor executes through Timelock.</small></div>
</div>
</div>

Governance controls the treasury and privileged protocol roles. The deployer is intended to be temporary and loses long-term authority after deployment handoff. `VerifyDeployment.s.sol` checks that the deployed system has the expected Timelock delay, Governor parameters, and role ownership.

## 7. Data Model and Storage Layout

### Upgradeable Token Storage

| Storage group | Field / owner                                          | Collision risk analysis                                                                    |
| ------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| OpenZeppelin  | ERC20 balances, allowances, total supply, name, symbol | Managed by OpenZeppelin upgradeable contracts and inherited in stable order.               |
| OpenZeppelin  | Pausable state                                         | Inherited before local fields and unchanged between V1 and V2.                             |
| OpenZeppelin  | AccessControl role admin and membership maps           | Inherited before local fields and unchanged between V1 and V2.                             |
| OpenZeppelin  | UUPS and Initializable state                           | Required for proxy safety and upgrade authorization.                                       |
| V1 local      | `address registry`                                     | First local project-defined variable.                                                      |
| V1 reserved   | `uint256[49] __gap`                                    | Reserved expansion space for future versions.                                              |
| V2 local      | `string complianceUri`                                 | Appended after V1 fields; tests confirm balances, roles, and registry survive the upgrade. |

### Non-Upgradeable Contract Storage

| Contract                | Key state                                                                                   | Notes                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `RwaGovernanceToken`    | Balances, votes checkpoints, permit nonces, delegation state, roles.                        | Timestamp clock gives human-readable governance windows.                             |
| `ReserveCertificateNFT` | ERC721 ownership, token URIs, `nextTokenId`, roles, pause state.                            | Certificates are not a legal title transfer; they are reserve evidence references.   |
| `TBillVault`            | ERC4626 share balances, total supply, immutable TBILL asset, roles, pause/reentrancy flags. | ERC4626 accounting is tested under deposits, mints, withdrawals, redeems, and yield. |
| `RwaStableAMM`          | Immutable tokens, reserves, last update timestamp, LP ERC20 balances and allowances.        | `k` invariant is tracked in invariant tests after swaps.                             |
| `OracleAdapter`         | Price feed, reserve feed, max staleness, roles.                                             | Business logic reads adapter functions, not raw aggregator contracts.                |
| `ProtocolTreasury`      | ERC20 owed balances, ETH owed balances, roles.                                              | Pull-over-push model avoids failed receiver loops.                                   |
| `ProtocolFactory`       | TBILL implementation address, role configuration.                                           | Deterministic address prediction is exposed for CREATE2 deployments.                 |
| `RwaGovernor`           | Proposal state, voting snapshots, quorum, Timelock operation IDs.                           | OpenZeppelin modules compose the full propose to execute lifecycle.                  |

## 8. Roles, Permissions, and Trust Assumptions

| Role / power       | Holder after deployment       | Capability                                                          | Risk if compromised                                                   | Mitigation                                                                            |
| ------------------ | ----------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Timelock admin     | Timelock                      | Root executor for privileged calls.                                 | Malicious successful proposal can change parameters or move treasury. | 2 day delay, public proposal trail, token voting checkpoints.                         |
| Token upgrader     | Timelock                      | Authorizes `TBillToken` UUPS upgrades.                              | Bad implementation can break token behavior.                          | Upgrade proposal delay and V1 to V2 storage tests.                                    |
| Issuer role        | Authorized issuer             | Mint `TBILL` against reserve evidence.                              | Over-minting if issuer is malicious or operationally compromised.     | Governance can revoke role; reserve certificates and oracle data are auditable.       |
| Vault manager      | Timelock / configured manager | Report yield into ERC4626 vault.                                    | False or unsupported yield reporting.                                 | SafeERC20 transfer requires actual TBILL movement into vault.                         |
| Oracle admin       | Timelock                      | Update feeds and max staleness.                                     | Bad feed can distort protocol readouts.                               | Timelock delay and explicit stale/invalid answer reverts.                             |
| Treasury scheduler | Timelock                      | Schedule token or ETH payments.                                     | Misallocation of treasury assets.                                     | Pull payments and governance execution trail.                                         |
| Pauser             | Timelock                      | Pause token, certificate, and vault flows during incident response. | Governance can halt user flows.                                       | Documented circuit breaker, delay for planned actions, limited to pausable contracts. |

Trust assumptions:

- Off-chain custody, legal ownership, and reserve attestations are outside the smart-contract scope.
- The testnet deployment uses mock feeds for demo; mainnet deployment must replace them with official production feeds.
- Base Sepolia gas and final addresses depend on deploy secrets that are intentionally not committed.
- A compromised deployer before role handoff is a serious risk; the deployment script and verification script are designed to make handoff explicit.

## 9. Design Patterns and Architecture Decisions

| Pattern                     | Where used                      | Why it is needed                                                                                 |
| --------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------ |
| Factory pattern             | `ProtocolFactory`               | Required to deploy asset proxies through CREATE and CREATE2, including deterministic prediction. |
| Proxy / UUPS                | `TBillToken`                    | RWA compliance metadata can evolve while keeping a stable token address.                         |
| Checks-Effects-Interactions | Treasury withdrawals, AMM flows | State is updated before external value transfer or protected by reentrancy guard.                |
| Pull-over-push payments     | `ProtocolTreasury`              | Payees withdraw, so a receiver cannot block a payout batch.                                      |
| Role-based access control   | Token, vault, oracle, treasury  | All privileged functions have explicit OpenZeppelin role checks.                                 |
| Pausable / circuit breaker  | Token, NFT, vault               | Governance can stop flows during compliance or oracle incidents.                                 |
| Oracle adapter abstraction  | `OracleAdapter`                 | Feed contracts can be replaced without rewriting business logic.                                 |
| Timelock                    | Governance admin layer          | Adds a 2 day public delay before privileged actions.                                             |
| ReentrancyGuard             | Vault, AMM, fixtures            | Protects value-moving entry points and demonstrates the fixed vulnerability case study.          |

### ADR-001: UUPS Only for the RWA Asset Token

Context: RWA compliance metadata can change, but upgradeability increases audit risk. Options considered were immutable token, transparent proxy, or UUPS proxy. Decision: use UUPS only for `TBillToken`; keep the vault, AMM, treasury, oracle, and Governor non-upgradeable. Consequence: the upgrade surface is isolated and governance-controlled.

### ADR-002: Timelock as Long-Term Administrator

Context: direct owner or deployer admin powers would violate the governance requirement and create an instant-change risk. Decision: privileged roles are handed to `TimelockController`. Consequence: users and reviewers can monitor queued operations before they execute.

### ADR-003: ERC4626 for Yield Representation

Context: tokenized yield needs consistent share accounting. Options were custom shares or ERC4626. Decision: ERC4626. Consequence: auditors can rely on a known standard, and the test suite can focus on rounding, share conversion, and withdrawal behavior.

### ADR-004: From-Scratch Constant Product AMM

Context: the course requires a DeFi primitive built from scratch. Decision: implement x\*y=k with 0.3% fee, LP shares, deadline checks, and slippage limits. Consequence: the surface is smaller than a full Uniswap fork but still demonstrates reserves, liquidity shares, swaps, and invariants.

### ADR-005: Chainlink-Compatible Adapter

Context: production feeds and testnet mocks should share the same interface. Decision: write an adapter around `latestRoundData` with staleness, zero answer, and negative answer checks. Consequence: tests can use mocks while production can replace feed addresses through governance.

### ADR-006: Pull Payments for Treasury

Context: pushing payments to arbitrary receivers can fail or re-enter. Decision: treasury records owed balances and lets receivers withdraw. Consequence: the treasury has clearer accounting and a narrower external-call surface.

## 10. Deployment and Verification Model

The deployment system is Foundry-only. `Deploy.s.sol` deploys mocks when needed, deploys the full protocol stack, performs role handoff, delegates initial governance voting power, and writes `deployments/<chainId>.json`. `VerifyDeployment.s.sol` reads that manifest and verifies the critical post-deployment invariants.

| Script                           | Purpose                                                                             |
| -------------------------------- | ----------------------------------------------------------------------------------- |
| `script/Deploy.s.sol`            | Idempotent Anvil/Base Sepolia deployment and manifest generation.                   |
| `script/UpgradeTBillToken.s.sol` | Governance-compatible upgrade path from V1 to V2.                                   |
| `script/VerifyDeployment.s.sol`  | Confirms Timelock delay, Governor parameters, role handoff, and deployed addresses. |
| `script/GasCompare.s.sol`        | Benchmarks gas-sensitive protocol operations and writes the gas report.             |

Required real deployment environment variables are documented in `.env.example`: `BASE_SEPOLIA_RPC_URL`, `PRIVATE_KEY`, `BASESCAN_API_KEY`, `WALLETCONNECT_PROJECT_ID`, `SUBGRAPH_DEPLOY_KEY`, and `MAINNET_RPC_URL`.

## 11. Frontend and Subgraph Architecture

The frontend is intentionally an operational protocol dashboard, not a marketing page. It exposes wallet connection, network switching, token balances, voting power, delegate address, vault shares/assets, AMM reserves, oracle data, issuer actions, proposal activity, and user-triggered write flows.

The subgraph indexes events into at least the required four entities and provides documented GraphQL queries. Indexed sections are used for activity and proposal state, while critical balances and protocol state are read directly from contracts.

| Frontend capability       | Source of truth              | Notes                                                                      |
| ------------------------- | ---------------------------- | -------------------------------------------------------------------------- |
| Wallet and network status | Wagmi / wallet provider      | Wrong network prompts the user to switch.                                  |
| Token balances            | Contracts through Viem       | Reads TBILL, voting power, delegate, vault shares, and AMM reserves.       |
| State-changing actions    | Contracts through wallet     | Deposit, withdraw, liquidity, swap, delegate, vote, and issuer mint flows. |
| Activity feed             | The Graph                    | Uses indexed events rather than direct contract reads.                     |
| Error messages            | Frontend transaction wrapper | Converts raw RPC and wallet rejection errors into readable user messages.  |

## 12. Engineering Readiness Checklist

| Area             | Status                                                                                    |
| ---------------- | ----------------------------------------------------------------------------------------- |
| Compile          | `forge build` passes.                                                                     |
| Tests            | `forge test` passes with 88 tests.                                                        |
| Coverage         | `forge coverage --ir-minimum` reports 92.31% line coverage for production contracts.      |
| Formatting       | `forge fmt --check` and Prettier are included in local checks and CI.                     |
| Security tooling | Slither is configured in CI and expected to report zero High and zero Medium findings.    |
| No Hardhat       | Repository guard fails if Hardhat config, dependency, script, or CI usage is introduced.  |
| Deployment       | Anvil deployment is verified; Base Sepolia deployment requires local secrets.             |
| Documentation    | Architecture, audit, gas, coverage, deployment verification, and presentation PDFs exist. |
