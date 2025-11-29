// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Agent Gateway 结算合约
/// @notice 用于记录每次 Agent 调用的链上支付信息，并按比例拆分给开发者 (provider) 和平台 (platform)
/// @dev 适配 Monad L1，使用原生代币 (Native Coin) 进行支付结算

contract AgentGatewaySettlement {
    /// @dev 每个 Agent 的基础信息
    struct AgentInfo {
        address provider; // Agent 提供者（开发者）地址
        uint96 feeBps; // 平台抽成费率（basis points，万分比，例如 500 = 5%）
        bool active; // Agent 是否可用
    }

    /// @dev 每次调用（一次支付）的记录
    struct PaymentRecord {
        address user; // 支付用户
        uint256 amount; // 本次调用支付的金额（原生代币最小单位）
        uint256 timestamp; // 记录时间
        bool exists; // 标记该 usageId 是否已经记录过，防止重复记账
    }

    /// @notice 合约拥有者，一般为平台控制者
    address public owner;

    /// @notice 平台手续费接收地址（平台收入最终会被转到这个地址）
    address public platformFeeRecipient;

    /// @notice Agent 配置表：agentId => AgentInfo
    mapping(bytes32 => AgentInfo) public agents;

    /// @notice 开发者可提取的余额：agentId => amount
    /// @dev 每次成功的 pay 会把 provider 拆分份额累加到这里
    mapping(bytes32 => uint256) public providerBalances;

    /// @notice 平台可提取的余额：amount
    uint256 public platformBalance;

    /// @notice 每次使用记录：usageId => PaymentRecord
    /// @dev usageId 通常由后端生成 (例如 hash(agentId, user, nonce))，用于幂等控制
    mapping(bytes32 => PaymentRecord) public payments;

    /// @notice 新的 Agent 被注册
    event AgentRegistered(bytes32 indexed agentId, address indexed provider, uint96 feeBps);

    /// @notice 已注册 Agent 的配置被更新
    event AgentUpdated(bytes32 indexed agentId, address indexed provider, uint96 feeBps, bool active);

    /// @notice 记录一次成功支付，对应一次 Agent 调用
    event PaymentRecorded(bytes32 indexed usageId, bytes32 indexed agentId, address indexed user, uint256 amount);

    /// @notice 开发者提取自己在某个 Agent 下累积的余额
    event ProviderWithdrawn(bytes32 indexed agentId, address indexed provider, uint256 amount);

    /// @notice 平台提取平台累积的手续费
    event PlatformWithdrawn(uint256 amount);

    /// @dev 仅合约 owner 可调用的修饰器
    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    /// @dev 仅对应 Agent 的 provider（开发者）可调用的修饰器
    modifier onlyProvider(bytes32 agentId) {
        require(agents[agentId].provider == msg.sender, "NOT_PROVIDER");
        _;
    }

    /// @param _platformFeeRecipient 平台手续费接收地址
    constructor(address _platformFeeRecipient) {
        owner = msg.sender;
        platformFeeRecipient = _platformFeeRecipient;
    }

    /// @notice 修改平台手续费接收地址
    function setPlatformFeeRecipient(address _recipient) external onlyOwner {
        platformFeeRecipient = _recipient;
    }

    /// @notice 注册新的 Agent，仅限开发者自己调用一次
    /// @param agentId Agent 唯一标识（建议由后端或前端统一生成，例如 keccak256(AgentURL...)）
    /// @param feeBps 平台抽成费率（万分比，500 = 5%）
    function registerAgent(
        bytes32 agentId,
        uint96 feeBps
    ) external {
        require(agentId != bytes32(0), "INVALID_AGENT_ID");
        require(feeBps <= 5000, "FEE_TOO_HIGH"); // 最大 50%

        AgentInfo storage info = agents[agentId];
        require(info.provider == address(0), "ALREADY_REGISTERED");

        info.provider = msg.sender;
        info.feeBps = feeBps;
        info.active = true;

        emit AgentRegistered(agentId, msg.sender, feeBps);
    }

    /// @notice 更新已注册 Agent 的费率和启用状态
    /// @dev 只能由 Agent 对应的 provider 调用
    function updateAgent(
        bytes32 agentId,
        uint96 feeBps,
        bool active
    ) external onlyProvider(agentId) {
        require(feeBps <= 5000, "FEE_TOO_HIGH");

        AgentInfo storage info = agents[agentId];
        info.feeBps = feeBps;
        info.active = active;

        emit AgentUpdated(agentId, msg.sender, feeBps, active);
    }

    /// @notice 用户支付原生代币以使用 Agent
    /// @param agentId 已注册的 Agent 标识
    /// @param usageId 本次使用的唯一 ID（例如 hash(agentId, user, nonce)）
    function pay(
        bytes32 agentId,
        bytes32 usageId
    ) external payable {
        uint256 amount = msg.value;
        require(amount > 0, "INVALID_AMOUNT");
        require(usageId != bytes32(0), "INVALID_USAGE_ID");
        require(!payments[usageId].exists, "USAGE_ALREADY_RECORDED"); // 防止同一个 usageId 被重复记账

        AgentInfo memory info = agents[agentId];
        require(info.provider != address(0), "AGENT_NOT_FOUND");
        require(info.active, "AGENT_INACTIVE");

        // 拆分为：平台手续费 + 开发者可提余额
        uint256 fee = (amount * info.feeBps) / 10000;
        uint256 providerAmount = amount - fee;

        providerBalances[agentId] += providerAmount;
        platformBalance += fee;

        payments[usageId] = PaymentRecord({
            user: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            exists: true
        });

        emit PaymentRecorded(usageId, agentId, msg.sender, amount);
    }

    /// @notice 开发者提取自己在指定 Agent 下累积的余额
    /// @param agentId 要提取的 Agent
    /// @param amount 提取数量
    function withdrawProvider(bytes32 agentId, uint256 amount) external onlyProvider(agentId) {
        require(amount > 0, "INVALID_AMOUNT");
        uint256 balance = providerBalances[agentId];
        require(balance >= amount, "INSUFFICIENT_BALANCE");

        providerBalances[agentId] = balance - amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "TRANSFER_FAILED");

        emit ProviderWithdrawn(agentId, msg.sender, amount);
    }

    /// @notice 平台提取自己累积的手续费收入
    /// @param amount 提取数量
    function withdrawPlatform(uint256 amount) external onlyOwner {
        require(amount > 0, "INVALID_AMOUNT");
        uint256 balance = platformBalance;
        require(balance >= amount, "INSUFFICIENT_BALANCE");

        platformBalance = balance - amount;
        
        (bool success, ) = payable(platformFeeRecipient).call{value: amount}("");
        require(success, "TRANSFER_FAILED");

        emit PlatformWithdrawn(amount);
    }
}


