# Deployment Verification Report

<div class="document-meta">
<strong>Target network:</strong> Base Sepolia<br>
<strong>Local verification network:</strong> Anvil chain ID 31337<br>
<strong>Deployment toolchain:</strong> Foundry scripts only<br>
<strong>Status:</strong> Local Anvil deployment verified. Base Sepolia deployment waits for private RPC, deployer key, and explorer API key.
</div>

## 1. Verification Purpose

This report documents the post-deployment checks that prove the deployed protocol matches the course requirements. The goal is to catch deployment mistakes that a normal compile or unit test cannot detect: wrong Timelock delay, wrong Governor parameters, forgotten deployer admin rights, missing treasury ownership, or incorrect proxy address wiring.

## 2. Scripts

| Script                           | Responsibility                                                                                       |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `script/Deploy.s.sol`            | Deploys the full protocol, performs role handoff, delegates initial votes, and writes manifest JSON. |
| `script/VerifyDeployment.s.sol`  | Reads deployment manifest and validates post-deployment role and governance invariants.              |
| `script/UpgradeTBillToken.s.sol` | Executes the V1 to V2 upgrade path for the UUPS token.                                               |
| `script/GasCompare.s.sol`        | Measures representative protocol operation gas and writes the gas report.                            |

## 3. Required Checks

| Check                  | Expected value                | Why it matters                                                          |
| ---------------------- | ----------------------------- | ----------------------------------------------------------------------- |
| Timelock delay         | 2 days                        | Gives users and reviewers a window before privileged execution.         |
| Governor voting delay  | 1 day                         | Prevents instant proposal voting.                                       |
| Governor voting period | 1 week                        | Gives voters time to react.                                             |
| Governor quorum        | 4%                            | Matches project requirement.                                            |
| Proposal threshold     | 1% of governance token supply | Reduces proposal spam.                                                  |
| TBILL admin/upgrader   | Timelock                      | Prevents deployer-controlled minting, pausing, or upgrades after setup. |
| Vault admin            | Timelock                      | Keeps yield and pause powers governance-controlled.                     |
| Treasury manager       | Timelock                      | Ensures treasury actions go through governance.                         |
| Timelock proposer      | Governor                      | Only successful proposals can be queued.                                |
| Timelock executor      | Open executor `address(0)`    | Anyone can execute once the Timelock delay has elapsed.                 |

## 4. Local Anvil Verification Output

```text
Deployment verification passed for chain 31337
Timelock 0x0165878A594ca255338adfa4d48449f69242Eb8F
Governor 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853
TBill proxy 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
```

## 5. Base Sepolia Deployment Inputs

Real Base Sepolia deployment is pending local secret configuration:

- `BASE_SEPOLIA_RPC_URL`
- `PRIVATE_KEY`
- `BASESCAN_API_KEY`
- funded deployer account
- optional `WALLETCONNECT_PROJECT_ID` for frontend deployment
- optional `SUBGRAPH_DEPLOY_KEY` for Subgraph Studio deployment

## 6. Final Submission Links

Paste verified Base Sepolia explorer links here after running:

```bash
npm run deploy:base-sepolia
npm run verify:base-sepolia
```

| Contract                    | Base Sepolia address | Explorer verification link |
| --------------------------- | -------------------- | -------------------------- |
| `TBillToken` proxy          | TBD                  | TBD                        |
| `TBillToken` implementation | TBD                  | TBD                        |
| `RwaGovernanceToken`        | TBD                  | TBD                        |
| `ReserveCertificateNFT`     | TBD                  | TBD                        |
| `TBillVault`                | TBD                  | TBD                        |
| `RwaStableAMM`              | TBD                  | TBD                        |
| `OracleAdapter`             | TBD                  | TBD                        |
| `ProtocolTreasury`          | TBD                  | TBD                        |
| `ProtocolFactory`           | TBD                  | TBD                        |
| `RwaGovernor`               | TBD                  | TBD                        |
| `TimelockController`        | TBD                  | TBD                        |
