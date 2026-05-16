# Coverage Report

<div class="document-meta">
<strong>Measurement:</strong> Foundry line, statement, branch, and function coverage<br>
<strong>Scope:</strong> Production contracts in <code>src/</code>, excluding mocks, tests, and scripts<br>
<strong>Requirement:</strong> At least 90% line coverage across contracts<br>
<strong>Status:</strong> Passing with 92.31% line coverage
</div>

## 1. Command

```bash
forge coverage --ir-minimum --report summary --no-match-coverage 'script|test|src/mocks'
```

`--ir-minimum` is used because Foundry coverage disables optimizer/viaIR by default, and the large deployment script otherwise hits Solidity stack-depth limits. The same command is documented for local review and CI consistency.

## 2. Coverage Summary

| Scope                                          |            Lines |       Statements |       Branches |      Functions |
| ---------------------------------------------- | ---------------: | ---------------: | -------------: | -------------: |
| Production contracts in `src/` excluding mocks | 92.31% (276/299) | 91.24% (250/274) | 34.41% (32/93) | 94.81% (73/77) |

## 3. Test Suite Evidence

<div class="metric-grid">
<div class="metric"><strong>88</strong><span>Foundry tests currently passing.</span></div>
<div class="metric"><strong>50+</strong><span>Unit tests cover public/external functions and revert paths.</span></div>
<div class="metric"><strong>10+</strong><span>Fuzz tests cover AMM, ERC4626, and governance paths.</span></div>
</div>

Additional coverage classes:

- Invariant tests cover AMM constant product behavior, ERC20 supply conservation, vault accounting, treasury accounting, and governance role safety.
- Fork hooks cover USDC, Uniswap V2 router, and Chainlink feed integrations when `MAINNET_RPC_URL` is present.
- Vulnerability case studies reproduce and fix reentrancy and missing access control.

## 4. Notes for Final Submission

Scripts, tests, and mock contracts are excluded from the graded production-contract denominator. If final code changes add new production branches, rerun coverage and update this report before submission.
