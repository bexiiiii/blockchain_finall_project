import "@rainbow-me/rainbowkit/styles.css";
import React from "react";
import ReactDOM from "react-dom/client";
import { RainbowKitProvider, getDefaultConfig } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { baseSepolia, foundry } from "wagmi/chains";
import { http } from "viem";
import App from "./App";
import "./styles.css";

const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID ?? "demo";

const config = getDefaultConfig({
  appName: "RWA T-Bill Protocol",
  projectId,
  chains: [baseSepolia, foundry],
  transports: {
    [baseSepolia.id]: http(import.meta.env.VITE_BASE_SEPOLIA_RPC_URL),
    [foundry.id]: http("http://127.0.0.1:8545"),
  },
  ssr: false,
});

const queryClient = new QueryClient();

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          <App />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>,
);
