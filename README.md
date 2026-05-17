# RWA T-Bill Tokenization Protocol

Full-stack decentralized protocol for tokenized T-Bills, built for the Blockchain Technologies 2 final project.

The repo uses Foundry + Anvil only for smart contracts. There is no Hardhat config, dependency, or CI step.

## Team Ownership

| Member               | Ownership                                                                |
| -------------------- | ------------------------------------------------------------------------ |
| Tokhtamishov Bekhruz | Solidity contracts, security controls, Foundry tests, deployment scripts |
| Zhangir Muslimov     | React dApp, subgraph, documentation, gas report, presentation            |

## Protocol Components

- `TBillToken`: UUPS upgradeable ERC20 RWA asset token with issuer minting, burning, pause controls, registry updates, and V1 to V2 path.
- `RwaGovernanceToken`: ERC20Votes + ERC20Permit governance token using timestamp checkpoints.
- `ReserveCertificateNFT`: ERC721 reserve certificate for off-chain collateral attestations.
- `TBillVault`: ERC4626 tokenized vault for T-Bill yield distribution.
- `RwaStableAMM`: from-scratch x\*y=k AMM with 0.3% fee, LP token, deadlines, and slippage protection.
- `OracleAdapter`: Chainlink-compatible price/reserve feeds with stale, zero, and negative-answer checks.
- `RwaGovernor` + `TimelockController`: 1 day voting delay, 1 week voting period, 4% quorum, 1% proposal threshold, 2 day timelock.
- `ProtocolFactory`: CREATE and CREATE2 deployment paths.
- `ProtocolTreasury`: Timelock-controlled pull-payment treasury.
- Vite React dApp with Wagmi, Viem, RainbowKit, MetaMask/WalletConnect support, and subgraph reads.
- The Graph subgraph with 8 entities and documented queries.

## Setup

```bash
npm install
npm --prefix frontend install
forge install foundry-rs/forge-std
```

Copy `.env.example` to `.env` and fill the deployment values when deploying to Base Sepolia.

## Checks

```bash
forge build
forge test
npm run coverage
npm run lint:sol
npm --prefix frontend run build
npm run subgraph:codegen
npm run subgraph:build
```

The current local suite has 88 passing Foundry tests:

- 80 protocol tests including unit and fuzz tests.
- 5 invariant tests.
- 3 fork integration tests that execute when `MAINNET_RPC_URL` is present and return early otherwise.

Current production-contract line coverage is 92.31% using:

```bash
forge coverage --ir-minimum --report summary --no-match-coverage 'script|test|src/mocks'
```

## Local Anvil Deployment

Terminal 1:

```bash
npm run anvil
```

Terminal 2:

```bash
npm run deploy:anvil
forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url http://127.0.0.1:8545
```

The deploy script writes `deployments/<chainId>.json`. Copy those addresses into frontend env variables:

```bash
VITE_TBILL_TOKEN=
VITE_SETTLEMENT_TOKEN=
VITE_GOVERNANCE_TOKEN=
VITE_VAULT=
VITE_AMM=
VITE_GOVERNOR=
VITE_ORACLE=
```

## Base Sepolia Deployment

Required:

- `BASE_SEPOLIA_RPC_URL`
- `PRIVATE_KEY`
- `BASESCAN_API_KEY`
- funded deployer account on Base Sepolia

```bash
npm run deploy:base-sepolia
npm run verify:base-sepolia
```

The script deploys Chainlink-compatible mock price/reserve feeds for the testnet demo. For production, replace the feed addresses with official Chainlink price/proof-of-reserve feeds through Timelock governance.

## Frontend

```bash
npm --prefix frontend run dev
```

The dApp reads balances, voting power, delegate address, vault assets/shares, AMM reserves, and oracle state. It writes vault deposits/withdrawals, AMM liquidity/swaps, governance delegation, and proposal votes.

### Frontend Interaction Flow

The frontend is designed as a governance-aware dashboard for interacting with the full RWA protocol stack.

Core interaction flows include:
- ERC20 asset balance tracking
- ERC4626 vault deposit and withdrawal execution
- AMM liquidity provisioning and token swap execution
- governance delegation and proposal voting
- oracle visibility and reserve state monitoring
- live indexed protocol analytics through The Graph subgraph

The interface uses Wagmi + Viem for contract interactions and RainbowKit for wallet onboarding and multi-wallet support.

Frontend state synchronization combines direct on-chain reads with indexed subgraph queries to reduce RPC overhead and improve dashboard responsiveness.

## Subgraph

Update addresses in `subgraph/subgraph.yaml` after deployment, then:

```bash
npm run subgraph:codegen
npm run subgraph:build
graph auth --studio "$SUBGRAPH_DEPLOY_KEY"
npm run subgraph:deploy
```

Documented GraphQL queries are in `subgraph/queries.md`.

## Documents

- Architecture: `docs/architecture/ARCHITECTURE.md` and `docs/architecture/ARCHITECTURE.pdf`
- Security audit: `docs/audit/SECURITY_AUDIT.md` and `docs/audit/SECURITY_AUDIT.pdf`
- Coverage: `docs/reports/coverage.md` and `docs/reports/coverage.pdf`
- Gas report: `docs/reports/gas-comparison.md` and `docs/reports/gas-comparison.pdf`
- Deployment verification: `docs/reports/deployment-verification.md` and `docs/reports/deployment-verification.pdf`
- Presentation slide deck: `docs/presentation/final-presentation.md` and `docs/presentation/final-presentation.pdf`

Generate PDF copies:

```bash
npm run docs:pdf
```

## Documentation Structure

The repository separates protocol logic, frontend integration, deployment artifacts, and reporting documents into dedicated directories for easier auditing and maintenance.

Key areas:
- `src/` — Solidity smart contracts
- `frontend/` — React dApp
- `subgraph/` — The Graph indexing configuration
- `docs/` — architecture, audit, gas, coverage, and deployment reports