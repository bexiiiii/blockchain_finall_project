import type { Address } from "viem";

const fallback = "0x0000000000000000000000000000000000000000" as const;

function addressFromEnv(value: string | undefined): Address {
  return (value && value.startsWith("0x") ? value : fallback) as Address;
}

export const contracts = {
  chainId: Number(import.meta.env.VITE_CHAIN_ID ?? 84532),
  tbill: addressFromEnv(import.meta.env.VITE_TBILL_TOKEN),
  settlementToken: addressFromEnv(import.meta.env.VITE_SETTLEMENT_TOKEN),
  governanceToken: addressFromEnv(import.meta.env.VITE_GOVERNANCE_TOKEN),
  vault: addressFromEnv(import.meta.env.VITE_VAULT),
  amm: addressFromEnv(import.meta.env.VITE_AMM),
  governor: addressFromEnv(import.meta.env.VITE_GOVERNOR),
  oracle: addressFromEnv(import.meta.env.VITE_ORACLE),
  subgraphUrl: import.meta.env.VITE_SUBGRAPH_URL ?? "",
};

export const proposalStates = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
] as const;
