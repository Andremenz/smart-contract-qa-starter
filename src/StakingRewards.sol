// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20Minimal } from "./MinimalERC20.sol";

/// @title StakingRewards
/// @notice Educational example for testing workflows. Not audited or production-ready.
contract StakingRewards {
    uint256 public constant REWARD_DURATION = 7 days;
    uint256 private constant PRECISION = 1e18;

    IERC20Minimal public immutable stakingToken;
    IERC20Minimal public immutable rewardToken;
    address public immutable owner;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    uint256 public rewardRate;
    uint256 public totalOutstandingRewards;
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _lock = 1;

    error Unauthorized();
    error ZeroAmount();
    error InsufficientStake();
    error RewardPeriodActive();
    error InsufficientRewardFunding();
    error TokenCallFailed();
    error ReentrantCall();
    error InvalidTokenAddress();
    error IdenticalTokens();
    error UnsupportedTokenBehavior();

    event Staked(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardPaid(address indexed account, uint256 reward);
    event RewardNotified(uint256 reward, uint256 rewardRate, uint256 periodFinish);

    constructor(address stakingToken_, address rewardToken_) {
        if (
            stakingToken_ == address(0) || rewardToken_ == address(0)
                || stakingToken_.code.length == 0 || rewardToken_.code.length == 0
        ) revert InvalidTokenAddress();
        if (stakingToken_ == rewardToken_) revert IdenticalTokens();

        stakingToken = IERC20Minimal(stakingToken_);
        rewardToken = IERC20Minimal(rewardToken_);
        owner = msg.sender;
    }

    modifier nonReentrant() {
        if (_lock != 1) revert ReentrantCall();
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier updateReward(address account) {
        uint256 applicableTime = _min(block.timestamp, periodFinish);

        // Reserve actual emissions while rewards are accruing to stakers.
        // This avoids undercounting caused by reward-per-token rounding.
        if (totalSupply > 0) {
            totalOutstandingRewards += (applicableTime - lastUpdateTime) * rewardRate;
        }

        uint256 updatedRewardPerToken = rewardPerToken();
        rewardPerTokenStored = updatedRewardPerToken;
        lastUpdateTime = applicableTime;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerTokenStored;
        uint256 applicableTime = _min(block.timestamp, periodFinish);
        return rewardPerTokenStored + ((applicableTime - lastUpdateTime) * rewardRate * PRECISION)
            / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return (balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account]))
            / PRECISION + rewards[account];
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        // This example supports exact-transfer, non-rebasing ERC-20s only.
        uint256 balanceBefore = stakingToken.balanceOf(address(this));

        // Effects before interaction: post-transfer token callbacks observe
        // matching staking-token custody and staking accounting.
        totalSupply += amount;
        balanceOf[msg.sender] += amount;

        _safeTransferFrom(stakingToken, msg.sender, address(this), amount);
        uint256 received = stakingToken.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert UnsupportedTokenBehavior();

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientStake();

        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stakingToken, msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            totalOutstandingRewards -= reward;
            _safeTransfer(rewardToken, msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Owner funds the next reward period. Reward tokens must already be in this contract.
    function notifyRewardAmount(uint256 reward) external nonReentrant updateReward(address(0)) {
        if (msg.sender != owner) revert Unauthorized();
        if (reward == 0) revert ZeroAmount();
        if (block.timestamp < periodFinish) revert RewardPeriodActive();

        uint256 newRate = reward / REWARD_DURATION;
        if (newRate == 0 || rewardToken.balanceOf(address(this)) < totalOutstandingRewards + reward)
        {
            revert InsufficientRewardFunding();
        }

        rewardRate = newRate;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARD_DURATION;
        emit RewardNotified(reward, newRate, periodFinish);
    }

    function _safeTransfer(IERC20Minimal token, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        _validateTokenCall(ok, data);
    }

    function _safeTransferFrom(IERC20Minimal token, address from, address to, uint256 amount)
        private
    {
        (bool ok, bytes memory data) = address(token)
            .call(abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, amount));
        _validateTokenCall(ok, data);
    }

    function _validateTokenCall(bool ok, bytes memory data) private pure {
        if (!ok) revert TokenCallFailed();
        if (data.length == 0) return;
        if (data.length < 32) revert TokenCallFailed();

        uint256 returnValue;
        assembly {
            returnValue := mload(add(data, 32))
        }

        if (returnValue != 1) revert TokenCallFailed();
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
