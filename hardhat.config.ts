import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

// 从 .env 中读取 Monad RPC，如果没配置则给一个明显的占位符，防止误连无效地址
const MONAD_RPC_URL =
  process.env.MONAD_RPC_URL || "https://your-monad-testnet-rpc.example";
const MONAD_PRIVATE_KEY = process.env.MONAD_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    monadTestnet: {
      // 这里直接使用上面的 MONAD_RPC_URL，建议在 .env 中填真实的测试网 RPC
      url: MONAD_RPC_URL,
      accounts: MONAD_PRIVATE_KEY ? [MONAD_PRIVATE_KEY] : []
    }
  }
};

export default config;


