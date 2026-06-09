// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IPositionManager {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

contract MultiDEXStaking is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    IPositionManager public immutable pancakePositionManager;
    IPositionManager public immutable uniswapPositionManager;

    struct RewardPool {
        uint256 totalStakedLiquidity;
        uint256 accRewardPerLiquidity;
        uint256 lastRewardTime;
        uint256 rewardRate;
        uint256 poolEndTime;
        bool isSet;
    }

    struct StakeInfo {
        address owner;
        uint256 tokenId;
        uint256 liquidity;
        uint256 stakedAt;
        bool isPancake;
    }

    mapping(uint256 => StakeInfo) public stakes;
    mapping(address => uint256[]) public userStakes;
    mapping(address => RewardPool) public rewardPools;
    mapping(uint256 => mapping(address => uint256)) public stakeRewardDebts; // tokenId => rewardToken => rewardDebt
    address[] public activeRewardTokens; // Array to track all active reward tokens
    mapping(address => bool) public isRewardTokenActive; // Mapping to check if a reward token is active

    uint256 public constant MIN_LOCK_FOR_REWARD = 72; // 72 hours in production
    bool public paused;

    event Staked(address indexed user, uint256 indexed tokenId, bool isPancake);
    event Unstaked(address indexed user, uint256 indexed tokenId);
    event Claimed(address indexed user, address indexed rewardToken, uint256 amount);
    event Paused();
    event Unpaused();
    event PoolExtended(address indexed rewardToken, uint256 newEndTime);

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(IPositionManager _pancakePositionManager, IPositionManager _uniswapPositionManager, address _initialOwner) Ownable(_initialOwner) {
        pancakePositionManager = _pancakePositionManager;
        uniswapPositionManager = _uniswapPositionManager;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function addRewardPool(address rewardToken, uint256 totalRewards, uint256 stakingDuration) external onlyOwner {
        require(!rewardPools[rewardToken].isSet && !isRewardTokenActive[rewardToken], "Reward token already set");
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), totalRewards);
        RewardPool storage pool = rewardPools[rewardToken];
        pool.totalStakedLiquidity = 0;
        pool.accRewardPerLiquidity = 0;
        pool.lastRewardTime = block.timestamp;
        pool.rewardRate = totalRewards / stakingDuration;
        pool.poolEndTime = block.timestamp + stakingDuration;
        pool.isSet = true;
        activeRewardTokens.push(rewardToken);
        isRewardTokenActive[rewardToken] = true;
    }

    function increaseCurrentReward(address rewardToken, uint256 additionalAmount) external onlyOwner {
        require(rewardPools[rewardToken].isSet, "Reward token not active");
        require(block.timestamp < rewardPools[rewardToken].poolEndTime, "Pool already ended");

        RewardPool storage pool = rewardPools[rewardToken];
        _updateRewardsForPool(rewardToken);

        uint256 remainingDuration = pool.poolEndTime - block.timestamp;
        require(remainingDuration > 0, "No remaining duration");

        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), additionalAmount);

        uint256 remainingRewards = pool.rewardRate * remainingDuration;
        uint256 newTotal = remainingRewards + additionalAmount;

        pool.rewardRate = newTotal / remainingDuration;
    }

    function stake(uint256 tokenId, bool isPancake) external nonReentrant whenNotPaused {
        IPositionManager positionManager = isPancake ? pancakePositionManager : uniswapPositionManager;

        positionManager.safeTransferFrom(msg.sender, address(this), tokenId);

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
        require(liquidity > 0, "Invalid liquidity amount");

        for (uint256 i = 0; i < activeRewardTokens.length; i++) {
            address rewardToken = activeRewardTokens[i];
            _updateRewardsForPool(rewardToken);
            rewardPools[rewardToken].totalStakedLiquidity += liquidity;
            stakeRewardDebts[tokenId][rewardToken] = (liquidity * rewardPools[rewardToken].accRewardPerLiquidity) / 1e18;
        }

        stakes[tokenId] = StakeInfo({
            owner: msg.sender,
            tokenId: tokenId,
            liquidity: liquidity,
            stakedAt: block.timestamp,
            isPancake: isPancake
        });

        userStakes[msg.sender].push(tokenId);
        emit Staked(msg.sender, tokenId, isPancake);
    }

    function claimRewards(uint256 tokenId, address rewardToken) external nonReentrant whenNotPaused {
        StakeInfo storage stakeInfo = stakes[tokenId];
        require(stakeInfo.owner == msg.sender, "Not owner");
        require(rewardPools[rewardToken].isSet, "Reward token not set");
        require(block.timestamp >= stakeInfo.stakedAt + MIN_LOCK_FOR_REWARD, "Lock not met for rewards");

        _updateRewardsForPool(rewardToken);

        uint256 pending = (stakeInfo.liquidity * rewardPools[rewardToken].accRewardPerLiquidity / 1e18) - stakeRewardDebts[tokenId][rewardToken];
        stakeRewardDebts[tokenId][rewardToken] = (stakeInfo.liquidity * rewardPools[rewardToken].accRewardPerLiquidity) / 1e18;

        if (pending > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, pending);
            emit Claimed(msg.sender, rewardToken, pending);
        }
    }

    function unstake(uint256 tokenId, address rewardToken) external nonReentrant whenNotPaused {
        StakeInfo storage stakeInfo = stakes[tokenId];
        require(stakeInfo.owner == msg.sender, "Not owner");
        require(rewardPools[rewardToken].isSet, "Reward token not set");

        _updateRewardsForPool(rewardToken);

        if (block.timestamp >= stakeInfo.stakedAt + MIN_LOCK_FOR_REWARD) {
            uint256 pending = (stakeInfo.liquidity * rewardPools[rewardToken].accRewardPerLiquidity / 1e18) - stakeRewardDebts[tokenId][rewardToken];
            if (pending > 0) {
                IERC20(rewardToken).safeTransfer(msg.sender, pending);
                emit Claimed(msg.sender, rewardToken, pending);
            }
        }

        for (uint256 i = 0; i < activeRewardTokens.length; i++) {
            rewardPools[activeRewardTokens[i]].totalStakedLiquidity -= stakeInfo.liquidity;
        }

        uint256 length = userStakes[msg.sender].length;
        for (uint256 i = 0; i < length; i++) {
            if (userStakes[msg.sender][i] == tokenId) {
                userStakes[msg.sender][i] = userStakes[msg.sender][length - 1];
                userStakes[msg.sender].pop();
                break;
            }
        }

        IPositionManager positionManager = stakeInfo.isPancake ? pancakePositionManager : uniswapPositionManager;
        positionManager.safeTransferFrom(address(this), msg.sender, tokenId);
        delete stakes[tokenId];
        emit Unstaked(msg.sender, tokenId);
    }

    function _updateRewardsForPool(address rewardToken) internal {
        RewardPool storage pool = rewardPools[rewardToken];
        if (pool.totalStakedLiquidity > 0 && block.timestamp > pool.lastRewardTime) {
            uint256 timeElapsed = block.timestamp > pool.poolEndTime ? pool.poolEndTime - pool.lastRewardTime : block.timestamp - pool.lastRewardTime;
            uint256 reward = timeElapsed * pool.rewardRate;
            pool.accRewardPerLiquidity += (reward * 1e18) / pool.totalStakedLiquidity;
        }
        pool.lastRewardTime = block.timestamp > pool.poolEndTime ? pool.poolEndTime : block.timestamp;
    }

    function extendPoolDuration(address rewardToken, uint256 additionalTime) external onlyOwner {
        require(rewardPools[rewardToken].isSet, "Reward pool not set");
        require(block.timestamp < rewardPools[rewardToken].poolEndTime, "Pool already ended");

        // Extend the pool's duration by the specified additional time
        rewardPools[rewardToken].poolEndTime += additionalTime;

        emit PoolExtended(rewardToken, rewardPools[rewardToken].poolEndTime);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getActiveRewardTokens() external view returns (address[] memory) {
        return activeRewardTokens;
    }

    function getUserStakes(address addr) external view returns (uint256[] memory) {
        return userStakes[addr];
    }

    function pendingReward(uint256 tokenId, address rewardToken) public view returns (uint256) {
        StakeInfo storage stakeInfo = stakes[tokenId];
        RewardPool storage pool = rewardPools[rewardToken];

        if (!pool.isSet || block.timestamp < stakeInfo.stakedAt + MIN_LOCK_FOR_REWARD) return 0;

        uint256 acc = pool.accRewardPerLiquidity;
        if (block.timestamp > pool.lastRewardTime && pool.totalStakedLiquidity > 0) {
            uint256 timeElapsed = block.timestamp > pool.poolEndTime ? pool.poolEndTime - pool.lastRewardTime : block.timestamp - pool.lastRewardTime;
            uint256 reward = timeElapsed * pool.rewardRate;
            acc += (reward * 1e18) / pool.totalStakedLiquidity;
        }

        return (stakeInfo.liquidity * acc / 1e18) - stakeRewardDebts[tokenId][rewardToken];
    }

    function withdrawLeftovers(address rewardToken) external onlyOwner {
        require(block.timestamp > rewardPools[rewardToken].poolEndTime, "Pool not ended");
        _updateRewardsForPool(rewardToken);
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransfer(msg.sender, balance);
    }

    function removeRewardPool(address rewardToken) external onlyOwner {
        RewardPool storage pool = rewardPools[rewardToken];
        require(pool.isSet, "Not set");
        require(block.timestamp > pool.poolEndTime, "Not ended");
        require(pool.totalStakedLiquidity == 0, "Has liquidity");

        pool.isSet = false;
        isRewardTokenActive[rewardToken] = false;
        for (uint256 i = 0; i < activeRewardTokens.length; i++) {
            if (activeRewardTokens[i] == rewardToken) {
                activeRewardTokens[i] = activeRewardTokens[activeRewardTokens.length - 1];
                activeRewardTokens.pop();
                break;
            }
        }
    }
}
