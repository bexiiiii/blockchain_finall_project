import { useMemo, useState } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Activity, Banknote, Coins, Landmark, ShieldCheck, Vote } from "lucide-react";
import { formatUnits, parseUnits, zeroAddress, type Address } from "viem";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { ammAbi, erc20Abi, governorAbi, oracleAbi, vaultAbi } from "./abi/protocol";
import { contracts, proposalStates } from "./config/contracts";

type Proposal = {
  id: string;
  proposalId: string;
  description: string;
  proposer: string;
  state: string;
};

function formatToken(value?: bigint, decimals = 18, digits = 4) {
  if (value === undefined) return "0";
  const formatted = formatUnits(value, decimals);
  const [whole, fraction = ""] = formatted.split(".");
  return fraction ? `${whole}.${fraction.slice(0, digits)}` : whole;
}

function getReadableError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("User rejected")) return "Transaction rejected in wallet.";
  if (message.includes("insufficient funds")) return "Insufficient balance for this transaction.";
  if (message.includes("ConnectorNotConnected")) return "Connect a wallet first.";
  if (message.includes("chain")) return "Wrong network. Switch to Base Sepolia or Anvil.";
  return message.split("\n")[0] || "Transaction failed.";
}

async function fetchSubgraph(url: string): Promise<Proposal[]> {
  if (!url) return [];
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      query: `{
        proposals(first: 10, orderBy: createdAt, orderDirection: desc) {
          id
          proposalId
          proposer
          description
          state
        }
      }`,
    }),
  });
  const json = await response.json();
  if (json.errors) throw new Error(json.errors[0]?.message ?? "Subgraph query failed");
  return json.data?.proposals ?? [];
}

export default function App() {
  const { address, chainId, isConnected } = useAccount();
  const { switchChain } = useSwitchChain();
  const { writeContractAsync, data: hash, error, isPending } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });
  const [amount, setAmount] = useState("100");
  const [usdcAmount, setUsdcAmount] = useState("100");
  const [proposalId, setProposalId] = useState("");
  const [support, setSupport] = useState(1);
  const [notice, setNotice] = useState("");
  const [subgraphError, setSubgraphError] = useState("");
  const [proposals, setProposals] = useState<Proposal[]>([]);

  const account = address ?? zeroAddress;
  const wrongNetwork = isConnected && chainId !== contracts.chainId;
  const txBusy = isPending || isConfirming;

  const { data: reads } = useReadContracts({
    contracts: [
      { address: contracts.tbill, abi: erc20Abi, functionName: "balanceOf", args: [account] },
      {
        address: contracts.governanceToken,
        abi: erc20Abi,
        functionName: "getVotes",
        args: [account],
      },
      {
        address: contracts.governanceToken,
        abi: erc20Abi,
        functionName: "delegates",
        args: [account],
      },
      { address: contracts.vault, abi: vaultAbi, functionName: "balanceOf", args: [account] },
      { address: contracts.vault, abi: vaultAbi, functionName: "totalAssets" },
      { address: contracts.amm, abi: ammAbi, functionName: "getReserves" },
      { address: contracts.oracle, abi: oracleAbi, functionName: "latestPrice" },
      { address: contracts.oracle, abi: oracleAbi, functionName: "latestReserve" },
    ],
    query: { enabled: isConnected },
  });

  const { data: governorState } = useReadContract({
    address: contracts.governor,
    abi: governorAbi,
    functionName: "state",
    args: proposalId ? [BigInt(proposalId)] : undefined,
    query: { enabled: Boolean(proposalId) },
  });

  const metrics = useMemo(() => {
    const reserves = reads?.[5]?.result as readonly [bigint, bigint] | undefined;
    const price = reads?.[6]?.result as readonly [bigint, bigint] | undefined;
    const reserve = reads?.[7]?.result as readonly [bigint, bigint] | undefined;
    return {
      tbillBalance: reads?.[0]?.result as bigint | undefined,
      votes: reads?.[1]?.result as bigint | undefined,
      delegate: (reads?.[2]?.result as Address | undefined) ?? zeroAddress,
      vaultShares: reads?.[3]?.result as bigint | undefined,
      vaultAssets: reads?.[4]?.result as bigint | undefined,
      reserve0: reserves?.[0],
      reserve1: reserves?.[1],
      price: price?.[0],
      reserve: reserve?.[0],
    };
  }, [reads]);

  async function runTx(action: () => Promise<unknown>, success: string) {
    try {
      setNotice("");
      await action();
      setNotice(success);
    } catch (txError) {
      setNotice(getReadableError(txError));
    }
  }

  async function refreshSubgraph() {
    try {
      setSubgraphError("");
      setProposals(await fetchSubgraph(contracts.subgraphUrl));
    } catch (fetchError) {
      setSubgraphError(getReadableError(fetchError));
    }
  }

  const parsedTbill = (() => {
    try {
      return parseUnits(amount || "0", 18);
    } catch {
      return 0n;
    }
  })();

  const parsedUsdc = (() => {
    try {
      return parseUnits(usdcAmount || "0", 6);
    } catch {
      return 0n;
    }
  })();

  return (
    <main>
      <header className="topbar">
        <div>
          <p className="eyebrow">Base Sepolia RWA protocol</p>
          <h1>Tokenized T-Bill Desk</h1>
        </div>
        <ConnectButton />
      </header>

      {wrongNetwork && (
        <section className="banner">
          <ShieldCheck size={18} />
          <span>Connected to chain {chainId}. Switch to Base Sepolia for deployed contracts.</span>
          <button onClick={() => switchChain({ chainId: contracts.chainId })}>Switch</button>
        </section>
      )}

      {(notice || error) && (
        <section className="message">{notice || getReadableError(error)}</section>
      )}

      <section className="metrics">
        <Metric icon={<Coins />} label="TBILL balance" value={formatToken(metrics.tbillBalance)} />
        <Metric icon={<Vote />} label="Voting power" value={formatToken(metrics.votes)} />
        <Metric icon={<Banknote />} label="Vault shares" value={formatToken(metrics.vaultShares)} />
        <Metric icon={<Landmark />} label="Vault assets" value={formatToken(metrics.vaultAssets)} />
        <Metric
          icon={<Activity />}
          label="TBILL / USDC reserves"
          value={`${formatToken(metrics.reserve0)} / ${formatToken(metrics.reserve1, 6)}`}
        />
        <Metric
          icon={<ShieldCheck />}
          label="Price / reserve feeds"
          value={`${formatToken(metrics.price, 8, 2)} / ${formatToken(metrics.reserve, 8, 2)}`}
        />
      </section>

      <section className="grid">
        <Panel title="Vault">
          <LabeledInput label="TBILL amount" value={amount} onChange={setAmount} />
          <div className="actions">
            <button
              disabled={!isConnected || txBusy || parsedTbill <= 0n}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.tbill,
                      abi: erc20Abi,
                      functionName: "approve",
                      args: [contracts.vault, parsedTbill],
                    }),
                  "Vault allowance transaction submitted.",
                )
              }
            >
              Approve
            </button>
            <button
              disabled={
                !isConnected ||
                txBusy ||
                parsedTbill <= 0n ||
                parsedTbill > (metrics.tbillBalance ?? 0n)
              }
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.vault,
                      abi: vaultAbi,
                      functionName: "deposit",
                      args: [parsedTbill, account],
                    }),
                  "Deposit transaction submitted.",
                )
              }
            >
              Deposit
            </button>
            <button
              disabled={!isConnected || txBusy || parsedTbill <= 0n}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.vault,
                      abi: vaultAbi,
                      functionName: "withdraw",
                      args: [parsedTbill, account, account],
                    }),
                  "Withdraw transaction submitted.",
                )
              }
            >
              Withdraw
            </button>
          </div>
        </Panel>

        <Panel title="AMM">
          <LabeledInput label="TBILL amount" value={amount} onChange={setAmount} />
          <LabeledInput label="USDC amount" value={usdcAmount} onChange={setUsdcAmount} />
          <div className="actions">
            <button
              disabled={!isConnected || txBusy || parsedTbill <= 0n}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.tbill,
                      abi: erc20Abi,
                      functionName: "approve",
                      args: [contracts.amm, parsedTbill],
                    }),
                  "AMM allowance transaction submitted.",
                )
              }
            >
              Approve TBILL
            </button>
            <button
              disabled={!isConnected || txBusy || parsedTbill <= 0n || parsedUsdc <= 0n}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.amm,
                      abi: ammAbi,
                      functionName: "addLiquidity",
                      args: [
                        parsedTbill,
                        parsedUsdc,
                        1n,
                        1n,
                        account,
                        BigInt(Math.floor(Date.now() / 1000) + 600),
                      ],
                    }),
                  "Liquidity transaction submitted.",
                )
              }
            >
              Add liquidity
            </button>
            <button
              disabled={!isConnected || txBusy || parsedTbill <= 0n}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.amm,
                      abi: ammAbi,
                      functionName: "swapExactIn",
                      args: [
                        contracts.tbill,
                        parsedTbill,
                        1n,
                        account,
                        BigInt(Math.floor(Date.now() / 1000) + 600),
                      ],
                    }),
                  "Swap transaction submitted.",
                )
              }
            >
              Swap TBILL
            </button>
          </div>
        </Panel>

        <Panel title="Governance">
          <div className="delegate">
            <span>Delegate</span>
            <strong>
              {metrics.delegate === zeroAddress
                ? "None"
                : `${metrics.delegate.slice(0, 6)}...${metrics.delegate.slice(-4)}`}
            </strong>
          </div>
          <LabeledInput label="Proposal ID" value={proposalId} onChange={setProposalId} />
          <select value={support} onChange={(event) => setSupport(Number(event.target.value))}>
            <option value={1}>For</option>
            <option value={0}>Against</option>
            <option value={2}>Abstain</option>
          </select>
          <p className="state">
            State: {governorState === undefined ? "Unknown" : proposalStates[governorState]}
          </p>
          <div className="actions">
            <button
              disabled={!isConnected || txBusy}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.governanceToken,
                      abi: erc20Abi,
                      functionName: "delegate",
                      args: [account],
                    }),
                  "Delegation transaction submitted.",
                )
              }
            >
              Self delegate
            </button>
            <button
              disabled={!isConnected || txBusy || !proposalId}
              onClick={() =>
                runTx(
                  () =>
                    writeContractAsync({
                      address: contracts.governor,
                      abi: governorAbi,
                      functionName: "castVote",
                      args: [BigInt(proposalId), support],
                    }),
                  "Vote transaction submitted.",
                )
              }
            >
              Vote
            </button>
          </div>
        </Panel>

        <Panel title="Subgraph Activity">
          <button onClick={refreshSubgraph}>Refresh indexed proposals</button>
          {subgraphError && <p className="error">{subgraphError}</p>}
          <div className="proposalList">
            {proposals.length === 0 ? (
              <p className="muted">No indexed proposals loaded.</p>
            ) : (
              proposals.map((proposal) => (
                <button
                  key={proposal.id}
                  className="proposal"
                  onClick={() => setProposalId(proposal.proposalId)}
                >
                  <span>{proposal.description || proposal.proposalId}</span>
                  <strong>{proposal.state}</strong>
                </button>
              ))
            )}
          </div>
        </Panel>
      </section>
    </main>
  );
}

function Metric({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="metric">
      <div className="metricIcon">{icon}</div>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="panel">
      <h2>{title}</h2>
      {children}
    </section>
  );
}

function LabeledInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label>
      <span>{label}</span>
      <input inputMode="decimal" value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}
