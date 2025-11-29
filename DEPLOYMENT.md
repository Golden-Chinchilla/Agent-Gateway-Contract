# Agent-Gateway-Contract 部署记录

## 1. 环境与前置条件

- Node.js: 推荐 >= 18
- 包管理器: yarn 1.x
- 已安装 Hardhat 及相关依赖（项目中已通过 `package.json` 配置）
- 准备一个 Monad Testnet 钱包（仅测试用）

## 2. 配置环境变量

在 `Agent-Gateway-Contract` 目录下创建 `.env`（本次已配置）：

```bash
MONAD_RPC_URL=https://testnet-rpc.monad.xyz
MONAD_PRIVATE_KEY=51f22fc0ebdcfcdafb8c6b9db6c59f3bdd1f897fab931bb009cddb207fd6ecea
PLATFORM_FEE_RECIPIENT=0xf1c303eb8b90028c265040520731b924697d595b
```

> 注意：以上私钥和地址仅为当前测试环境示例，生产环境务必更换为安全的钱包并妥善保管。

## 3. 安装依赖

```bash
cd Agent-Gateway-Contract
yarn
```

## 4. 编译合约

```bash
yarn build
# 等价于：yarn hardhat compile
```

## 5. 部署到 Monad Testnet

使用 Hardhat 内置的脚本：

```bash
yarn deploy:monad-testnet
# 等价于：yarn hardhat run scripts/deploy.ts --network monadTestnet
```

本次部署输出：

```text
Deploying contracts with account: 0xF1c303eB8B90028C265040520731B924697d595b
AgentGatewaySettlement deployed to: 0x0366A65155606b662f8896a065bd0e246F4CCEc4
```

## 6. 关键合约信息

- 合约名称: `AgentGatewaySettlement`
- 部署网络: Monad Testnet (`monadTestnet`)
- 部署地址: `0x0366A65155606b662f8896a065bd0e246F4CCEc4`
- 平台手续费接收地址 (`platformFeeRecipient`): `0xf1c303eb8b90028c265040520731b924697d595b`

后续在 dApp 项目中需要使用该合约地址进行链上结算调用。

