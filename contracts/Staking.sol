// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Staking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant FEE_DENOMINATOR = 100;
    uint256 public constant PRECISION_FACTOR = 1000000000000000000000000; // 1e24
    uint256 public constant MULTIPLIER_DENOMINATOR = 1000000; // 1e6
    uint256 public constant DAY_DURATION = 1; // 86400 = 1 day in seconds
    uint256 public constant QUARTER_YEAR_DURATION = 10 days; // 7,776,000: ~90 days in seconds
    uint256 public constant MIN_LOCK_FOR_REWARD = 72; // 72 hours in production

    uint256 public poolEndTime;
    uint256 public extensionStartTime;
    uint256[4] public periodEndTimestamp;

    mapping(address => bool) public isAllowedToken;
    mapping(address => uint256) public totalStaked;
    mapping(address => uint256) public accTokenPerShare;
    mapping(address => uint256) public lastActionTime;
    mapping(address => uint256) public rewardPerSecond;
    mapping(address => uint256[4]) public rewardPerSecondAfter;
    mapping(address => uint256) public extensionRewardPerSecond;
    mapping(address => uint256) public leftovers;

    mapping(address => uint256) public totalStakes; // number of stakes per user
    mapping(address => mapping(uint256 => StakeInfo)) public stakeInfo;

    struct StakeInfo {
        address stakeToken;
        uint256 actualAmount;
        uint256 amount;
        uint256 enteredAt;
        uint256 lockedUntil;
        uint256 multiplier;
        uint256 rewardTaken;
    }

    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 lockInDays);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 reward);
    event Claimed(address indexed user, address indexed token, uint256 reward);
    event Paused();
    event Unpaused();

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    modifier onlyWhenActive() {
        require(!paused(), "Staking is paused");
        _;
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused();
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused();
    }

    function setPoolParameters() external onlyOwner {
        require(poolEndTime == 0, "Pool already set");
        poolEndTime = block.timestamp + (QUARTER_YEAR_DURATION * 4);
        periodEndTimestamp[0] = block.timestamp + QUARTER_YEAR_DURATION;
        periodEndTimestamp[1] = block.timestamp + (QUARTER_YEAR_DURATION * 2);
        periodEndTimestamp[2] = block.timestamp + (QUARTER_YEAR_DURATION * 3);
        periodEndTimestamp[3] = block.timestamp + (QUARTER_YEAR_DURATION * 4);
    }

    function addAllowedToken(address token, uint256 rewardAmountPerYear) external onlyOwner {
        require(!isAllowedToken[token], "Token already allowed");
        require(poolEndTime > 0, "Pool parameters not set");
        isAllowedToken[token] = true;
        uint256 amountNow = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(_msgSender(), address(this), rewardAmountPerYear);
        uint256 actualRewardAmount = IERC20(token).balanceOf(address(this)) - amountNow;
        rewardPerSecond[token] = (actualRewardAmount * 4) / (10 * QUARTER_YEAR_DURATION);
        for (uint256 i = 0; i < 3; i++) {
            rewardPerSecondAfter[token][i] = (actualRewardAmount * (3 - i)) / (10 * QUARTER_YEAR_DURATION);
        }
        leftovers[token] = actualRewardAmount - (
            (rewardPerSecond[token] + rewardPerSecondAfter[token][0] + rewardPerSecondAfter[token][1] + rewardPerSecondAfter[token][2]) * QUARTER_YEAR_DURATION
        );
        lastActionTime[token] = block.timestamp;
    }

    function increaseCurrentReward(address token, uint256 amount) external onlyOwner {
        require(isAllowedToken[token], "Token not allowed");
        require(poolEndTime > block.timestamp, "Pool ended");
        require(amount > 0, "Invalid reward amount");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 remainingTime = poolEndTime - block.timestamp;
        require(remainingTime > 0, "No time left");

        uint256 newRPS = amount / remainingTime;
        require(newRPS > 0, "Reward per second too low");

        if (extensionStartTime == 0) {
            rewardPerSecond[token] += newRPS;
        } else {
            extensionRewardPerSecond[token] += newRPS;
        }
    }

    function deposit(address token, uint256 amount, uint256 lockInDays) external nonReentrant onlyWhenActive {
        require(isAllowedToken[token], "Token not allowed");
        require(poolEndTime > block.timestamp, "Pool ended");
        require(amount > 0, "Cannot stake zero amount");
        require(lockInDays > 6 && lockInDays < 366, "Invalid lock period");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        amount = _takeFee(token, amount, 2);
        require(amount > 0, "Low deposit");

        _updateRPSForToken(token);

        uint256 multiplier = MULTIPLIER_DENOMINATOR + (((lockInDays - 7) * MULTIPLIER_DENOMINATOR) / 358);
        uint256 stakeAmount = amount * multiplier;
        totalStaked[token] += stakeAmount;

        StakeInfo storage stake = stakeInfo[msg.sender][totalStakes[msg.sender]];
        totalStakes[msg.sender]++;
        stake.stakeToken = token;
        stake.actualAmount = amount;
        stake.amount = stakeAmount;
        stake.enteredAt = block.timestamp;
        stake.lockedUntil = block.timestamp + (lockInDays * DAY_DURATION);
        stake.multiplier = multiplier;
        stake.rewardTaken = (stakeAmount * accTokenPerShare[token]) / PRECISION_FACTOR;

        emit Deposited(msg.sender, token, amount, lockInDays);
    }

    function withdraw(uint256 stakeID) external nonReentrant {
        require(stakeID < totalStakes[msg.sender], "Invalid ID");
        StakeInfo storage s = stakeInfo[msg.sender][stakeID];
        require(s.amount > 0, "Withdrawn");

        address token = s.stakeToken;
        _updateRPSForToken(token);

        uint256 reward = 0;
        if (block.timestamp - s.enteredAt >= MIN_LOCK_FOR_REWARD) {
            reward = (s.amount * accTokenPerShare[token]) / PRECISION_FACTOR - s.rewardTaken;
            if (reward > 0) IERC20(token).safeTransfer(msg.sender, reward);
        }

        uint256 amountToTransfer = _takeFee(token, s.actualAmount, 2);
        IERC20(token).safeTransfer(msg.sender, amountToTransfer);

        totalStaked[token] -= s.amount;
        delete stakeInfo[msg.sender][stakeID];

        emit Withdrawn(msg.sender, token, amountToTransfer, reward);
    }

    function claim(uint256 stakeID) external nonReentrant onlyWhenActive {
        require(stakeID < totalStakes[msg.sender], "Invalid ID");
        StakeInfo storage s = stakeInfo[msg.sender][stakeID];
        require(s.amount > 0, "Withdrawn");
        require(block.timestamp - s.enteredAt >= MIN_LOCK_FOR_REWARD, "Too early to claim");

        address token = s.stakeToken;
        _updateRPSForToken(token);

        uint256 toTransfer = (s.amount * accTokenPerShare[token]) / PRECISION_FACTOR - s.rewardTaken;
        s.rewardTaken = (s.amount * accTokenPerShare[token]) / PRECISION_FACTOR;

        IERC20(token).safeTransfer(msg.sender, toTransfer);
        emit Claimed(msg.sender, token, toTransfer);
    }

    function pendingReward(address account, uint256 stakeID) external view returns (uint256) {
        if (stakeID >= totalStakes[account]) return 0;
        StakeInfo storage s = stakeInfo[account][stakeID];
        if (block.timestamp - s.enteredAt < MIN_LOCK_FOR_REWARD) return 0;

        address token = s.stakeToken;
        if (!isAllowedToken[token] || poolEndTime == 0) return 0;

        uint256 endTime = block.timestamp > poolEndTime ? poolEndTime : block.timestamp;
        uint256 adjusted = getAdjustedAccTokenPerShare(token, endTime);
        return (s.amount * adjusted) / PRECISION_FACTOR - s.rewardTaken;
    }

    function getAdjustedAccTokenPerShare(address token, uint256 endTime) private view returns (uint256) {
        uint256 adjusted = accTokenPerShare[token];
        uint256 start = lastActionTime[token];
        if (endTime <= start) return adjusted;

        uint256 current = start;
        while (current < endTime) {
            uint256 next = endTime;
            if (current < periodEndTimestamp[0]) next = Math.min(periodEndTimestamp[0], endTime);
            else if (current < periodEndTimestamp[1]) next = Math.min(periodEndTimestamp[1], endTime);
            else if (current < periodEndTimestamp[2]) next = Math.min(periodEndTimestamp[2], endTime);
            else if (current < (extensionStartTime == 0 ? poolEndTime : extensionStartTime)) next = Math.min(extensionStartTime == 0 ? poolEndTime : extensionStartTime, endTime);
            else if (extensionStartTime != 0 && current < poolEndTime) next = Math.min(poolEndTime, endTime);

            uint256 delta = next - current;
            uint256 rps = getRewardRateAt(token, current);
            uint256 reward = delta * rps;

            if (totalStaked[token] > 0) adjusted += (reward * PRECISION_FACTOR) / totalStaked[token];
            current = next;
        }

        return adjusted;
    }

    function getRewardRateAt(address token, uint256 timestamp) private view returns (uint256) {
        if (timestamp < periodEndTimestamp[0]) return rewardPerSecond[token];
        else if (timestamp < periodEndTimestamp[1]) return rewardPerSecondAfter[token][0];
        else if (timestamp < periodEndTimestamp[2]) return rewardPerSecondAfter[token][1];
        else if (timestamp < (extensionStartTime == 0 ? poolEndTime : extensionStartTime)) return rewardPerSecondAfter[token][2];
        else if (extensionStartTime != 0 && timestamp < poolEndTime) return extensionRewardPerSecond[token];
        else return 0;
    }

    function _updateRPSForToken(address token) private {
        if (poolEndTime == 0 || block.timestamp <= lastActionTime[token]) return;

        uint256 start = lastActionTime[token];
        uint256 end = block.timestamp > poolEndTime ? poolEndTime : block.timestamp;
        if (end <= start) return;

        uint256 transferBack = 0;
        uint256 current = start;

        while (current < end) {
            uint256 next = end;
            if (current < periodEndTimestamp[0]) next = Math.min(periodEndTimestamp[0], end);
            else if (current < periodEndTimestamp[1]) next = Math.min(periodEndTimestamp[1], end);
            else if (current < periodEndTimestamp[2]) next = Math.min(periodEndTimestamp[2], end);
            else if (current < (extensionStartTime == 0 ? poolEndTime : extensionStartTime)) next = Math.min(extensionStartTime == 0 ? poolEndTime : extensionStartTime, end);
            else if (extensionStartTime != 0 && current < poolEndTime) next = Math.min(poolEndTime, end);

            uint256 delta = next - current;
            uint256 rps = getRewardRateAt(token, current);
            uint256 reward = delta * rps;

            if (totalStaked[token] == 0) transferBack += reward;
            else accTokenPerShare[token] += (reward * PRECISION_FACTOR) / totalStaked[token];

            current = next;
        }

        if (transferBack > 0) IERC20(token).safeTransfer(owner(), transferBack);
        lastActionTime[token] = block.timestamp;
    }

    function extendPool(uint256 newEndTime, address[] memory tokens, uint256[] memory additionalRewards) external onlyOwner {
        require(newEndTime > poolEndTime && newEndTime > block.timestamp, "Invalid end time");
        require(tokens.length == additionalRewards.length, "Length mismatch");
        require(extensionStartTime == 0, "Already extended");

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            require(isAllowedToken[token], "Token not allowed");
            _updateRPSForToken(token);
        }

        uint256 oldEnd = poolEndTime;
        extensionStartTime = oldEnd;
        poolEndTime = newEndTime;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amt = additionalRewards[i];
            require(amt > 0, "Invalid reward");
            IERC20(token).safeTransferFrom(_msgSender(), address(this), amt);
            extensionRewardPerSecond[token] = amt / (newEndTime - oldEnd);
            require(extensionRewardPerSecond[token] > 0, "Too low");
        }
    }

    function _takeFee(address token, uint256 amount, uint256 fee) private returns (uint256) {
        uint256 feeAmt = (amount * fee) / FEE_DENOMINATOR;
        IERC20(token).safeTransfer(owner(), feeAmt);
        return amount - feeAmt;
    }

    function withdrawLeftovers(address token) external onlyOwner {
        require(block.timestamp > poolEndTime, "Not ended");
        _updateRPSForToken(token);
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), bal);
    }

    function removeAllowedToken(address token) external onlyOwner {
        require(isAllowedToken[token], "Not allowed");
        isAllowedToken[token] = false;
    }
}
