# RWA T-Bill Tokenization Protocol

Full-Stack Decentralized Protocol - Blockchain Technologies 2 Final Project

<div class="metric-grid">
<div class="metric"><strong>Option C</strong><span>RWA tokenization platform</span></div>
<div class="metric"><strong>Foundry</strong><span>Anvil-first, no Hardhat</span></div>
<div class="metric"><strong>Base Sepolia</strong><span>L2 deployment target</span></div>
</div>

---

# Problem and Product

- Tokenize a simplified T-Bill reserve product as `TBILL`
- Keep minting issuer-gated and reserve-evidence driven
- Give users a vault, AMM liquidity, governance, and indexed activity
- Build a protocol another engineer can test, audit, deploy, and extend

---

# Requirement Coverage

| Course requirement | Protocol implementation                             |
| ------------------ | --------------------------------------------------- |
| Upgradeability     | UUPS `TBillToken`, V1 to V2 upgrade test            |
| Token standards    | ERC20Votes, ERC20Permit, ERC721, ERC4626            |
| DeFi primitive     | From-scratch x\*y=k AMM with 0.3% fee               |
| Oracle             | Chainlink-compatible adapter with staleness reverts |
| Governance         | Governor + 2 day Timelock lifecycle                 |
| Indexing and UI    | The Graph plus Vite React dApp                      |

---

# Architecture at a Glance

<div class="flow-row">
<div class="step">Frontend<small>RainbowKit, Wagmi, Viem, network checks</small></div>
<div class="step">Core Protocol<small>TBILL, vault, AMM, oracle, treasury</small></div>
<div class="step">Governance<small>Votes token, Governor, Timelock</small></div>
<div class="step">Data Layer<small>Subgraph entities and GraphQL queries</small></div>
<div class="step">Deployment<small>Foundry scripts for Anvil and Base Sepolia</small></div>
</div>

---

# Smart Contracts

- `TBillToken`: upgradeable RWA ERC20 with issuer minting
- `TBillVault`: ERC4626 vault for tokenized yield
- `RwaStableAMM`: x\*y=k liquidity and swaps
- `OracleAdapter`: price and reserve feeds with freshness checks
- `RwaGovernor` and `TimelockController`: DAO-controlled admin layer
- `ProtocolFactory`: CREATE and CREATE2 asset deployment

---

# Upgradeability Design

- Only the RWA asset token is upgradeable to keep upgrade risk narrow
- V1 stores core ERC20, roles, pause state, registry, and reserved gap
- V2 appends `complianceUri` without reordering inherited storage
- Upgrade authority is `UPGRADER_ROLE`, handed to Timelock after deploy
- Foundry test proves V1 state survives `upgradeToAndCall`

---

# RWA Minting and Reserve Evidence

<div class="flow-row">
<div class="step">Reserve docs<small>Off-chain custody evidence exists</small></div>
<div class="step">Certificate<small>Issuer mints ERC721 metadata URI</small></div>
<div class="step">Oracle read<small>Adapter checks feed freshness</small></div>
<div class="step">Mint TBILL<small>`ISSUER_ROLE` required</small></div>
<div class="step">Index event<small>Subgraph records transfer and certificate</small></div>
</div>

---

# ERC4626 Vault

- Users deposit `TBILL` and receive ERC4626 vault shares
- Yield is reported by a role-gated manager through real token transfer
- Deposit, mint, withdraw, redeem, and yield flows are `nonReentrant`
- Rounding behavior is covered with fuzz tests
- Vault actions are indexed by the subgraph

---

# AMM Built from Scratch

- Constant product invariant: `reserve0 * reserve1 = k`
- Swap fee: 0.3%, retained in the pool for LPs
- LP token accounting for add and remove liquidity
- Slippage protection with `amountOutMin`
- Deadline protection for stale transactions
- Invariant tests verify `k` never decreases after swaps

---

# Oracle and Governance

- Oracle adapter rejects stale, zero, negative, and incomplete feed data
- Governance token uses ERC20Votes + ERC20Permit
- Timestamp clock gives human-readable voting windows
- Voting delay: 1 day
- Voting period: 1 week
- Quorum: 4%, proposal threshold: 1%, Timelock delay: 2 days

---

# Security Model

| Control               | Implementation                                                  |
| --------------------- | --------------------------------------------------------------- |
| Privileged functions  | OpenZeppelin AccessControl or Governor/Timelock                 |
| Reentrancy            | `ReentrancyGuard` and CEI on value-moving flows                 |
| ERC20 transfers       | SafeERC20 in protocol contracts                                 |
| Forbidden primitives  | No `tx.origin`, no ETH `transfer/send`, no timestamp randomness |
| Vulnerability studies | Reentrancy and access-control before/after tests                |

---

# Testing Evidence

<div class="metric-grid">
<div class="metric"><strong>88</strong><span>Total Foundry tests pass</span></div>
<div class="metric"><strong>92.31%</strong><span>Line coverage across production contracts</span></div>
<div class="metric"><strong>5+</strong><span>Invariant categories including AMM, vault, treasury, roles</span></div>
</div>

- Unit tests cover public/external functions and revert paths
- Fuzz tests cover swaps, ERC4626 rounding, and voting power
- Fork hooks cover USDC, Uniswap V2 router, and Chainlink feed integrations

---

# Frontend dApp

- Wallet connection through RainbowKit with MetaMask and WalletConnect support
- Wrong-network detection and switch prompt
- Reads balances, voting power, delegate address, vault state, AMM reserves, oracle data
- Writes deposit, withdraw, add liquidity, swap, delegate, vote, and issuer actions
- Formats wallet rejection, insufficient balance, and RPC failures into readable messages

---

# Subgraph and Data Model

- Indexes asset transfers, vault deposits and withdrawals, swaps, liquidity positions, proposals, votes, and treasury payments
- Provides documented GraphQL queries for demo and grading review
- Frontend activity section reads indexed data from The Graph rather than only contract state
- Contract state remains source of truth; subgraph is an indexed read layer

---

# Deployment and DevOps

- Foundry scripts: `Deploy.s.sol`, `UpgradeTBillToken.s.sol`, `VerifyDeployment.s.sol`, `GasCompare.s.sol`
- Deployment manifests written to `deployments/<chainId>.json`
- CI runs compile, tests, coverage, formatting, Solhint, Slither, frontend build, and no-Hardhat guard
- Base Sepolia deploy requires local secrets and block explorer API key
- Anvil deploy and verification already run locally

---

# Gas and Optimization

| Operation          | Local gas | Optimization note                       |
| ------------------ | --------: | --------------------------------------- |
| TBill mint         |    26,003 | Role-gated ERC20 mint path              |
| Vault deposit      |    79,670 | ERC4626 share accounting plus SafeERC20 |
| AMM addLiquidity   |   152,599 | LP mint, reserve sync, transfer checks  |
| AMM swapExactIn    |    17,308 | Constant-product math and fee path      |
| Oracle latestPrice |     2,736 | Read-only adapter validation            |

---

# Demo Flow

<div class="flow-row">
<div class="step">Connect<small>Wallet connects to Anvil or Base Sepolia</small></div>
<div class="step">Inspect<small>Balances, votes, vault shares, reserves</small></div>
<div class="step">Deposit/Swap<small>State-changing protocol transaction</small></div>
<div class="step">Govern<small>Delegate and cast a vote</small></div>
<div class="step">Index<small>Review activity through subgraph view</small></div>
</div>

---

# Team Ownership

| Team member          | Primary ownership                                           | Defense responsibility                                      |
| -------------------- | ----------------------------------------------------------- | ----------------------------------------------------------- |
| Tokhtamishov Bekhruz | Contracts, security, tests, deployment scripts              | Contract architecture, vulnerabilities, governance, testing |
| Zhangir Muslimov     | Frontend, subgraph, documentation, presentation, gas report | UI flows, indexing, diagrams, deployment docs, user demo    |

Both team members must understand the whole system at architecture level for Q&A.

---

# Defense Talking Points

- Why UUPS is limited to `TBillToken` instead of every contract
- How Timelock removes direct deployer admin control
- How ERC20Votes checkpoints defend against flash-loan voting
- Why testnet reserve feeds are mocks and what production replacement requires
- How AMM and vault invariants are tested
- How frontend state differs from subgraph indexed activity

---

# Final Status

<div class="metric-grid">
<div class="metric"><strong>Implemented</strong><span>Full smart contract, frontend, subgraph, docs, CI, and scripts</span></div>
<div class="metric"><strong>Verified</strong><span>Anvil deploy, verification script, build, test, coverage, subgraph build</span></div>
<div class="metric"><strong>Remaining</strong><span>Base Sepolia secrets, final deploy, explorer links, final Slither appendix</span></div>
</div>
