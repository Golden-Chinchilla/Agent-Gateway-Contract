// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Agent Gateway 结算合约
/// @notice 用于记录每次 Agent 调用的链上支付信息，并按比例拆分给开发者 (provider) 和平台 (platform)

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract AgentGatewaySettlement {
    /// @dev 每个 Agent 的基础信息
    struct AgentInfo {
        address provider; // Agent 提供者（开发者）地址
        address token; // 收费所使用的 ERC20 Token 地址
        uint96 feeBps; // 平台抽成费率（basis points，万分比，例如 500 = 5%）
        bool active; // Agent 是否可用
    }

    /// @dev 每次调用（一次支付）的记录
    struct PaymentRecord {
        address user; // 支付用户
        uint256 amount; // 本次调用支付的金额（token 最小单位）
        uint256 timestamp; // 记录时间
        bool exists; // 标记该 usageId 是否已经记录过，防止重复记账
    }

    /// @notice 合约拥有者，一般为平台控制者
    address public owner;

    /// @notice 平台手续费接收地址（平台收入最终会被转到这个地址）
    address public platformFeeRecipient;

    /// @notice Agent 配置表：agentId => AgentInfo
    mapping(bytes32 => AgentInfo) public agents;

    /// @notice 开发者可提取的余额：agentId => (token => amount)
    /// @dev 每次成功的 recordPayment 会把 provider 拆分份额累加到这里
    mapping(bytes32 => mapping(address => uint256)) public providerBalances;

    /// @notice 平台可提取的余额：token => amount
    mapping(address => uint256) public platformBalances;

    /// @notice 每次使用记录：usageId => PaymentRecord
    /// @dev usageId 通常由后端生成 (例如 hash(agentId, user, nonce))，用于幂等控制
    mapping(bytes32 => PaymentRecord) public payments;

    /// @notice 新的 Agent 被注册
    event AgentRegistered(bytes32 indexed agentId, address indexed provider, address token, uint96 feeBps);

    /// @notice 已注册 Agent 的配置被更新（token / fee / active）
    event AgentUpdated(bytes32 indexed agentId, address indexed provider, address token, uint96 feeBps, bool active);

    /// @notice 记录一次成功支付，对应一次 Agent 调用
    event PaymentRecorded(bytes32 indexed usageId, bytes32 indexed agentId, address indexed user, uint256 amount, address token);

    /// @notice 开发者提取自己在某个 Agent 下累积的余额
    event ProviderWithdrawn(bytes32 indexed agentId, address indexed provider, address token, uint256 amount);

    /// @notice 平台提取平台累积的手续费
    event PlatformWithdrawn(address indexed token, uint256 amount);

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
    /// @param token 该 Agent 使用的收费 Token（ERC20）
    /// @param feeBps 平台抽成费率（万分比，500 = 5%）
    function registerAgent(
        bytes32 agentId,
        address token,
        uint96 feeBps
    ) external {
        require(agentId != bytes32(0), "INVALID_AGENT_ID");
        require(token != address(0), "INVALID_TOKEN");
        require(feeBps <= 5000, "FEE_TOO_HIGH"); // 最大 50%

        AgentInfo storage info = agents[agentId];
        require(info.provider == address(0), "ALREADY_REGISTERED");

        info.provider = msg.sender;
        info.token = token;
        info.feeBps = feeBps;
        info.active = true;

        emit AgentRegistered(agentId, msg.sender, token, feeBps);
    }

    /// @notice 更新已注册 Agent 的 token、费率和启用状态
    /// @dev 只能由 Agent 对应的 provider 调用
    function updateAgent(
        bytes32 agentId,
        address token,
        uint96 feeBps,
        bool active
    ) external onlyProvider(agentId) {
        require(token != address(0), "INVALID_TOKEN");
        require(feeBps <= 5000, "FEE_TOO_HIGH");

        AgentInfo storage info = agents[agentId];
        info.token = token;
        info.feeBps = feeBps;
        info.active = active;

        emit AgentUpdated(agentId, msg.sender, token, feeBps, active);
    }

    /// @notice Called by backend after verifying on-chain payment.
    /// @param agentId 已注册的 Agent 标识
    /// @param user 支付方地址（链上交易的 from）
    /// @param amount 支付金额（ERC20 的最小单位）
    /// @param usageId 本次使用的唯一 ID（例如 hash(agentId, user, nonce)）
    function recordPayment(
        bytes32 agentId,
        address user,
        uint256 amount,
        bytes32 usageId
    ) external {
        require(user != address(0), "INVALID_USER");
        require(amount > 0, "INVALID_AMOUNT");
        require(usageId != bytes32(0), "INVALID_USAGE_ID");
        require(!payments[usageId].exists, "USAGE_ALREADY_RECORDED"); // 防止同一个 usageId 被重复记账

        AgentInfo memory info = agents[agentId];
        require(info.provider != address(0), "AGENT_NOT_FOUND");
        require(info.active, "AGENT_INACTIVE");

        // 拆分为：平台手续费 + 开发者可提余额
        uint256 fee = (amount * info.feeBps) / 10000;
        uint256 providerAmount = amount - fee;

        providerBalances[agentId][info.token] += providerAmount;
        platformBalances[info.token] += fee;

        payments[usageId] = PaymentRecord({
            user: user,
            amount: amount,
            timestamp: block.timestamp,
            exists: true
        });

        emit PaymentRecorded(usageId, agentId, user, amount, info.token);
    }

    /// @notice 开发者提取自己在指定 Agent & Token 下累积的余额
    /// @param agentId 要提取的 Agent
    /// @param token 要提取的 Token（必须是该 Agent 收费 token）
    /// @param amount 提取数量
    function withdrawProvider(bytes32 agentId, address token, uint256 amount) external onlyProvider(agentId) {
        require(amount > 0, "INVALID_AMOUNT");
        uint256 balance = providerBalances[agentId][token];
        require(balance >= amount, "INSUFFICIENT_BALANCE");

        providerBalances[agentId][token] = balance - amount;
        require(IERC20(token).transfer(msg.sender, amount), "TRANSFER_FAILED");

        emit ProviderWithdrawn(agentId, msg.sender, token, amount);
    }

    /// @notice 平台提取自己累积的手续费收入
    /// @param token 要提取的 Token
    /// @param amount 提取数量
    function withdrawPlatform(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "INVALID_AMOUNT");
        uint256 balance = platformBalances[token];
        require(balance >= amount, "INSUFFICIENT_BALANCE");

        platformBalances[token] = balance - amount;
        require(IERC20(token).transfer(platformFeeRecipient, amount), "TRANSFER_FAILED");

        emit PlatformWithdrawn(token, amount);
    }
}


