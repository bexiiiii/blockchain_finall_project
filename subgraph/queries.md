# Documented GraphQL Queries

```graphql
query RecentTransfers {
  assetTransfers(first: 10, orderBy: timestamp, orderDirection: desc) {
    from
    to
    value
    txHash
  }
}
```

```graphql
query VaultActions {
  vaultActions(first: 20, orderBy: timestamp, orderDirection: desc) {
    action
    caller
    assets
    shares
  }
}
```

```graphql
query RecentSwaps {
  swaps(first: 20, orderBy: timestamp, orderDirection: desc) {
    trader
    tokenIn
    amountIn
    amountOut
  }
}
```

```graphql
query Governance {
  proposals(first: 10, orderBy: createdAt, orderDirection: desc) {
    proposalId
    proposer
    description
    state
    votes {
      voter
      support
      weight
    }
  }
}
```

```graphql
query TreasuryPayments {
  treasuryPayments(first: 20, orderBy: timestamp, orderDirection: desc) {
    paymentType
    token
    payee
    amount
    status
  }
}
```
