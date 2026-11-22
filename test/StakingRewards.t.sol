// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../src/MinimalERC20.sol";
import { StakingRewards } from "../src/StakingRewards.sol";

contract StakingRewardsTest is Test {
    MockERC20 internal stakeToken;
    MockERC20 internal rewardToken;
    StakingRewards internal staking;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK", 18);
        rewardToken = new MockERC20("Reward", "RWD", 18);
        staking = new StakingRewards(address(stakeToken), address(rewardToken));

        stakeToken.mint(alice, 1_000_000 ether);
        stakeToken.mint(bob, 1_000_000 ether);
        rewardToken.mint(address(this), 10_000_000 ether);
        rewardToken.transfer(address(staking), 10_000_000 ether);
        vm.prank(alice);
        stakeToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        stakeToken.approve(address(staking), type(uint256).max);
    }

    function _startRewards(uint256 amount) internal {
        staking.notifyRewardAmount(amount);
    }

    function testStakeAndWithdrawUpdatesAccounting() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        assertEq(staking.totalSupply(), 100 ether);
        assertEq(staking.balanceOf(alice), 100 ether);
        staking.withdraw(40 ether);
        vm.stopPrank();
        assertEq(staking.totalSupply(), 60 ether);
        assertEq(staking.balanceOf(alice), 60 ether);
        assertEq(stakeToken.balanceOf(alice), 1_000_000 ether - 60 ether);
        assertEq(stakeToken.balanceOf(address(staking)), 60 ether);
    }

    function testRewardsAccrueAndCanBeClaimed() public {
        uint256 reward = 700 ether;
        _startRewards(reward);
        vm.prank(alice);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 3 days);
        uint256 expected = staking.rewardRate() * 3 days;
        assertApproxEqAbs(staking.earned(alice), expected, 1);
        uint256 beforeBalance = rewardToken.balanceOf(alice);
        vm.prank(alice);
        staking.getReward();
        assertApproxEqAbs(rewardToken.balanceOf(alice) - beforeBalance, expected, 1);
        assertEq(staking.rewards(alice), 0);
    }

    function testFuzzStakeWithdraw(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000 ether);
        vm.startPrank(alice);
        staking.stake(amount);
        staking.withdraw(amount);
        vm.stopPrank();
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakeToken.balanceOf(address(staking)), 0);
    }

    function testRevertOnZeroStake() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.ZeroAmount.selector);
        staking.stake(0);
    }

    function testRevertOnZeroWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.ZeroAmount.selector);
        staking.withdraw(0);
    }

    function testRevertWhenWithdrawingMoreThanStaked() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.InsufficientStake.selector);
        staking.withdraw(1);
    }

    function testOnlyOwnerCanNotifyRewards() public {
        vm.prank(alice);
        vm.expectRevert(StakingRewards.Unauthorized.selector);
        staking.notifyRewardAmount(100 ether);
    }

    function testCannotNotifyDuringActivePeriod() public {
        staking.notifyRewardAmount(700 ether);
        vm.expectRevert(StakingRewards.RewardPeriodActive.selector);
        staking.notifyRewardAmount(100 ether);
    }

    function testCannotClaimSameRewardTwice() public {
        staking.notifyRewardAmount(700 ether);
        vm.prank(alice);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 7 days);
        vm.prank(alice);
        staking.getReward();
        uint256 afterFirstClaim = rewardToken.balanceOf(alice);
        vm.prank(alice);
        staking.getReward();
        assertEq(rewardToken.balanceOf(alice), afterFirstClaim);
    }

    function testCannotReuseFundsReservedForUnclaimedRewards() public {
        uint256 periodReward = 700 ether;

        MockERC20 limitedRewardToken = new MockERC20("Limited Reward", "LRWD", 18);

        StakingRewards limitedStaking =
            new StakingRewards(address(stakeToken), address(limitedRewardToken));

        limitedRewardToken.mint(address(limitedStaking), periodReward);

        vm.prank(alice);
        stakeToken.approve(address(limitedStaking), type(uint256).max);

        limitedStaking.notifyRewardAmount(periodReward);

        vm.prank(alice);
        limitedStaking.stake(100 ether);

        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        limitedStaking.stake(1 ether);

        assertGt(limitedStaking.earned(alice), 0);
        assertGt(limitedStaking.totalOutstandingRewards(), 0);

        vm.expectRevert(StakingRewards.InsufficientRewardFunding.selector);
        limitedStaking.notifyRewardAmount(periodReward);

        vm.prank(alice);
        limitedStaking.getReward();

        assertEq(limitedStaking.rewards(alice), 0);
        assertEq(limitedStaking.totalOutstandingRewards(), 0);
        assertGt(limitedRewardToken.balanceOf(alice), 0);
    }

    function testFrequentCheckpointsDoNotUnderstateOutstandingRewards() public {
        // One reward-token wei per second over the seven-day period.
        staking.notifyRewardAmount(604800);

        vm.prank(alice);
        staking.stake(3);

        // Bob triggers global checkpoints without having any stake.
        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 1);
            vm.prank(bob);
            staking.getReward();
        }

        uint256 aliceEarned = staking.earned(alice);
        uint256 reserved = staking.totalOutstandingRewards();

        assertEq(aliceEarned, 3);
        assertEq(reserved, 4);
        assertGe(reserved, aliceEarned);
    }

    function testMultipleStakersAndPartialWithdrawalsPreserveRewardReserve() public {
        staking.notifyRewardAmount(700 ether);

        vm.prank(alice);
        staking.stake(100 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        staking.stake(300 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(alice);
        staking.withdraw(40 ether);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);
        uint256 totalEarned = aliceEarned + bobEarned;
        uint256 reserved = staking.totalOutstandingRewards();

        assertGt(aliceEarned, 0);
        assertGt(bobEarned, 0);
        assertGe(reserved, totalEarned);
    }
}
