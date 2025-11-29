import { ethers } from "hardhat";

// 简单的部署脚本：将 AgentGatewaySettlement 部署到指定网络（例如 Monad Testnet）
async function main() {
  // 使用第一个 Signer 作为部署账号
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with account:", deployer.address);

  // 平台手续费接收地址：优先使用 .env 中的配置，否则回退为部署账号地址
  const platformFeeRecipient =
    process.env.PLATFORM_FEE_RECIPIENT || deployer.address;

  // 获取合约工厂并部署
  const Settlement = await ethers.getContractFactory("AgentGatewaySettlement");
  const settlement = await Settlement.deploy(platformFeeRecipient);

  await settlement.waitForDeployment();

  console.log(
    "AgentGatewaySettlement deployed to:",
    await settlement.getAddress()
  );
}

// 捕获异常，防止脚本无提示退出
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});


