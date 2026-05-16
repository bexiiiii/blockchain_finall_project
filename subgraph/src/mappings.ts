import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { Transfer, RegistryUpdated } from "../generated/TBillToken/TBillToken";
import { Deposit, Withdraw, YieldReported } from "../generated/TBillVault/TBillVault";
import {
  LiquidityAdded,
  LiquidityRemoved,
  Swap as SwapEvent,
} from "../generated/RwaStableAMM/RwaStableAMM";
import {
  ProposalCreated,
  ProposalExecuted,
  ProposalQueued,
  VoteCast as VoteCastEvent,
} from "../generated/RwaGovernor/RwaGovernor";
import {
  EthPaymentScheduled,
  EthPaymentWithdrawn,
  TokenPaymentScheduled,
  TokenPaymentWithdrawn,
} from "../generated/ProtocolTreasury/ProtocolTreasury";
import {
  Asset,
  AssetTransfer,
  LiquidityPosition,
  Proposal,
  Swap,
  TreasuryPayment,
  VaultAction,
  VoteCast,
} from "../generated/schema";

const ZERO = "0x0000000000000000000000000000000000000000";

function eventId(event: ethereum.Event): string {
  return event.transaction.hash.toHexString().concat("-").concat(event.logIndex.toString());
}

function loadAsset(event: ethereum.Event): Asset {
  let asset = Asset.load(event.address.toHexString());
  if (asset == null) {
    asset = new Asset(event.address.toHexString());
    asset.totalMinted = BigInt.zero();
    asset.totalBurned = BigInt.zero();
  }
  asset.updatedAt = event.block.timestamp;
  return asset;
}

export function handleTransfer(event: Transfer): void {
  let asset = loadAsset(event);
  if (event.params.from.toHexString() == ZERO) {
    asset.totalMinted = asset.totalMinted.plus(event.params.value);
  }
  if (event.params.to.toHexString() == ZERO) {
    asset.totalBurned = asset.totalBurned.plus(event.params.value);
  }
  asset.save();

  let transfer = new AssetTransfer(eventId(event));
  transfer.from = event.params.from;
  transfer.to = event.params.to;
  transfer.value = event.params.value;
  transfer.blockNumber = event.block.number;
  transfer.timestamp = event.block.timestamp;
  transfer.txHash = event.transaction.hash;
  transfer.save();
}

export function handleRegistryUpdated(event: RegistryUpdated): void {
  let asset = loadAsset(event);
  asset.registry = event.params.newRegistry;
  asset.save();
}

export function handleDeposit(event: Deposit): void {
  let action = new VaultAction(eventId(event));
  action.action = "Deposit";
  action.caller = event.params.sender;
  action.receiver = event.params.owner;
  action.owner = event.params.owner;
  action.assets = event.params.assets;
  action.shares = event.params.shares;
  action.timestamp = event.block.timestamp;
  action.txHash = event.transaction.hash;
  action.save();
}

export function handleWithdraw(event: Withdraw): void {
  let action = new VaultAction(eventId(event));
  action.action = "Withdraw";
  action.caller = event.params.sender;
  action.receiver = event.params.receiver;
  action.owner = event.params.owner;
  action.assets = event.params.assets;
  action.shares = event.params.shares;
  action.timestamp = event.block.timestamp;
  action.txHash = event.transaction.hash;
  action.save();
}

export function handleYieldReported(event: YieldReported): void {
  let action = new VaultAction(eventId(event));
  action.action = "YieldReported";
  action.caller = event.params.reporter;
  action.receiver = event.params.reporter;
  action.owner = event.params.reporter;
  action.assets = event.params.assets;
  action.shares = BigInt.zero();
  action.timestamp = event.block.timestamp;
  action.txHash = event.transaction.hash;
  action.save();
}

function loadPosition(provider: Address): LiquidityPosition {
  let id = provider.toHexString();
  let position = LiquidityPosition.load(id);
  if (position == null) {
    position = new LiquidityPosition(id);
    position.provider = provider;
    position.liquidity = BigInt.zero();
    position.amount0 = BigInt.zero();
    position.amount1 = BigInt.zero();
  }
  return position;
}

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let position = loadPosition(event.params.provider);
  position.liquidity = position.liquidity.plus(event.params.liquidity);
  position.amount0 = position.amount0.plus(event.params.amount0);
  position.amount1 = position.amount1.plus(event.params.amount1);
  position.updatedAt = event.block.timestamp;
  position.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let position = loadPosition(event.params.provider);
  position.liquidity = position.liquidity.minus(event.params.liquidity);
  position.amount0 = position.amount0.minus(event.params.amount0);
  position.amount1 = position.amount1.minus(event.params.amount1);
  position.updatedAt = event.block.timestamp;
  position.save();
}

export function handleSwap(event: SwapEvent): void {
  let swap = new Swap(eventId(event));
  swap.trader = event.params.trader;
  swap.tokenIn = event.params.tokenIn;
  swap.amountIn = event.params.amountIn;
  swap.amountOut = event.params.amountOut;
  swap.to = event.params.to;
  swap.timestamp = event.block.timestamp;
  swap.txHash = event.transaction.hash;
  swap.save();
}

export function handleProposalCreated(event: ProposalCreated): void {
  let proposal = new Proposal(event.params.proposalId.toString());
  proposal.proposalId = event.params.proposalId;
  proposal.proposer = event.params.proposer;
  proposal.description = event.params.description;
  proposal.state = "Pending";
  proposal.voteStart = event.params.voteStart;
  proposal.voteEnd = event.params.voteEnd;
  proposal.createdAt = event.block.timestamp;
  proposal.save();
}

export function handleVoteCast(event: VoteCastEvent): void {
  let vote = new VoteCast(eventId(event));
  vote.proposal = event.params.proposalId.toString();
  vote.voter = event.params.voter;
  vote.support = event.params.support;
  vote.weight = event.params.weight;
  vote.reason = event.params.reason;
  vote.timestamp = event.block.timestamp;
  vote.save();

  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal != null && proposal.state == "Pending") {
    proposal.state = "Active";
    proposal.save();
  }
}

export function handleProposalQueued(event: ProposalQueued): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal != null) {
    proposal.state = "Queued";
    proposal.queuedAt = event.block.timestamp;
    proposal.save();
  }
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal != null) {
    proposal.state = "Executed";
    proposal.executedAt = event.block.timestamp;
    proposal.save();
  }
}

function saveTreasuryPayment(
  event: ethereum.Event,
  paymentType: string,
  token: Bytes | null,
  payee: Bytes,
  amount: BigInt,
  status: string,
): void {
  let payment = new TreasuryPayment(eventId(event));
  payment.paymentType = paymentType;
  payment.token = token;
  payment.payee = payee;
  payment.amount = amount;
  payment.status = status;
  payment.timestamp = event.block.timestamp;
  payment.txHash = event.transaction.hash;
  payment.save();
}

export function handleTokenPaymentScheduled(event: TokenPaymentScheduled): void {
  saveTreasuryPayment(
    event,
    "Token",
    event.params.token,
    event.params.payee,
    event.params.amount,
    "Scheduled",
  );
}

export function handleTokenPaymentWithdrawn(event: TokenPaymentWithdrawn): void {
  saveTreasuryPayment(
    event,
    "Token",
    event.params.token,
    event.params.payee,
    event.params.amount,
    "Withdrawn",
  );
}

export function handleEthPaymentScheduled(event: EthPaymentScheduled): void {
  saveTreasuryPayment(event, "ETH", null, event.params.payee, event.params.amount, "Scheduled");
}

export function handleEthPaymentWithdrawn(event: EthPaymentWithdrawn): void {
  saveTreasuryPayment(event, "ETH", null, event.params.payee, event.params.amount, "Withdrawn");
}
