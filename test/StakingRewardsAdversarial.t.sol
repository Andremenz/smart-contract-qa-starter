// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { StakingRewards } from "../src/StakingRewards.sol";
import { AdversarialERC20 } from "./AdversarialERC20.sol";

contract StakingRewardsAdversarialTest is Test {
    AdversarialERC20 internal stakeToken;
    AdversarialERC20 internal rewardToken;
    StakingRewards internal staking;

    address internal alice = makeAddr("alice");

    function setUp() public {
        stakeToken = new AdversarialERC20();
        rewardToken = new AdversarialERC20();
        staking = new StakingRewards(address(stakeToken), address(rewardToken));

        stakeToken.mint(alice, 1_000 ether);
        rewardToken.mint(address(staking), 10_000 ether);

        vm.prank(alice);
        stakeToken.approve(address(staking), type(uint256).max);
    }

    function testRejectsExternallyOwnedAccountAsToken() public {
        vm.expectRevert(StakingRewards.InvalidTokenAddress.selector);
        new StakingRewards(address(0x1234), address(rewardToken));
    }

    function testRejectsZeroTokenAddress() public {
        vm.expectRevert(StakingRewards.InvalidTokenAddress.selector);
        new StakingRewards(address(0), address(rewardToken));
    }

    function testRejectsSameStakingAndRewardToken() public {
        vm.expectRevert(StakingRewards.IdenticalTokens.selector);
        new StakingRewards(address(stakeToken), address(stakeToken));
    }

    function testFalseReturningTransferFromRevertsAndRollsBackAccounting() public {
        stakeToken.configureReturns(false, true);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.TokenCallFailed.selector);
        staking.stake(10 ether);

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakeToken.balanceOf(address(staking)), 0);
    }

    function testRevertingTransferFromRevertsAndRollsBackAccounting() public {
        stakeToken.configureReverts(false, true);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.TokenCallFailed.selector);
        staking.stake(10 ether);

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakeToken.balanceOf(address(staking)), 0);
    }

    function testFeeOnTransferStakeIsRejected() public {
        stakeToken.configureFee(200);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.UnsupportedTokenBehavior.selector);
        staking.stake(100 ether);

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakeToken.balanceOf(address(staking)), 0);
    }

    function testReentrantStakeCallbackIsBlocked() public {
        bytes memory payload = abi.encodeWithSelector(StakingRewards.stake.selector, 1 ether);
        stakeToken.configureCallback(address(staking), payload);

        vm.prank(alice);
        staking.stake(10 ether);

        assertTrue(stakeToken.callbackAttempted());
        assertFalse(stakeToken.callbackSucceeded());
        assertEq(staking.totalSupply(), 10 ether);
        assertEq(staking.balanceOf(alice), 10 ether);
    }

    function testReentrantWithdrawCallbackIsBlocked() public {
        vm.prank(alice);
        staking.stake(10 ether);

        bytes memory payload = abi.encodeWithSelector(StakingRewards.withdraw.selector, 1 ether);
        stakeToken.configureCallback(address(staking), payload);

        vm.prank(alice);
        staking.withdraw(1 ether);

        assertTrue(stakeToken.callbackAttempted());
        assertFalse(stakeToken.callbackSucceeded());
        assertEq(staking.totalSupply(), 9 ether);
        assertEq(staking.balanceOf(alice), 9 ether);
    }

    function testReentrantGetRewardCallbackIsBlocked() public {
        staking.notifyRewardAmount(700 ether);

        vm.prank(alice);
        staking.stake(10 ether);

        vm.warp(block.timestamp + 1 days);

        bytes memory payload = abi.encodeWithSelector(StakingRewards.getReward.selector);
        rewardToken.configureCallback(address(staking), payload);

        vm.prank(alice);
        staking.getReward();

        assertTrue(rewardToken.callbackAttempted());
        assertFalse(rewardToken.callbackSucceeded());
        assertGt(rewardToken.balanceOf(alice), 0);
        assertEq(staking.rewards(alice), 0);
    }

    function testReentrantNotifyRewardCallbackIsBlocked() public {
        bytes memory payload =
            abi.encodeWithSelector(StakingRewards.notifyRewardAmount.selector, 1 ether);
        stakeToken.configureCallback(address(staking), payload);

        vm.prank(alice);
        staking.stake(10 ether);

        assertTrue(stakeToken.callbackAttempted());
        assertFalse(stakeToken.callbackSucceeded());
        assertEq(staking.totalSupply(), 10 ether);
    }

    function testFalseReturningWithdrawTransferRevertsAndRestoresStakeAccounting() public {
        vm.prank(alice);
        staking.stake(10 ether);

        stakeToken.configureReturns(true, false);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.TokenCallFailed.selector);
        staking.withdraw(10 ether);

        assertEq(staking.totalSupply(), 10 ether);
        assertEq(staking.balanceOf(alice), 10 ether);
        assertEq(stakeToken.balanceOf(address(staking)), 10 ether);
    }

    function testFalseReturningRewardTransferRestoresClaimAndReserve() public {
        staking.notifyRewardAmount(700 ether);

        vm.prank(alice);
        staking.stake(10 ether);

        vm.warp(block.timestamp + 1 days);

        // Persist accrued rewards before testing the failed claim.
        vm.prank(alice);
        staking.stake(1 ether);

        rewardToken.configureReturns(true, false);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.TokenCallFailed.selector);
        staking.getReward();

        assertGt(staking.rewards(alice), 0);
        assertGt(staking.totalOutstandingRewards(), 0);
        assertEq(rewardToken.balanceOf(alice), 0);
    }

    function testMalformedTransferFromReturnRevertsAndRollsBack() public {
        stakeToken.configureMalformedReturns(false, true);

        uint256 aliceBefore = stakeToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.TokenCallFailed.selector);
        staking.stake(10 ether);

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(alice), 0);
        assertEq(stakeToken.balanceOf(address(staking)), 0);
        assertEq(stakeToken.balanceOf(alice), aliceBefore);
    }

    function testMalformedTransferReturnRevertsAndRestoresAccounting() public {
        vm.prank(alice);
        staking.stake(10 ether);

        stakeToken.configureMalformedReturns(true, false);

        vm.prank(alice);
        vm.expectRevert(StakingRewards.TokenCallFailed.selector);
        staking.withdraw(10 ether);

        assertEq(staking.totalSupply(), 10 ether);
        assertEq(staking.balanceOf(alice), 10 ether);
        assertEq(stakeToken.balanceOf(address(staking)), 10 ether);
    }

    function testReadOnlyCallbackObservesConsistentStakeState() public {
        StakingReadOnlyObserver observer = new StakingReadOnlyObserver(staking, stakeToken);

        bytes memory payload = abi.encodeWithSelector(observer.observe.selector, alice);
        stakeToken.configureCallback(address(observer), payload);

        vm.prank(alice);
        staking.stake(10 ether);

        assertTrue(stakeToken.callbackAttempted());
        assertTrue(stakeToken.callbackSucceeded());

        assertEq(observer.observedTokenBalance(), 10 ether);
        assertEq(observer.observedTotalSupply(), 10 ether);
        assertEq(observer.observedAccountStake(), 10 ether);

        assertEq(staking.totalSupply(), 10 ether);
        assertEq(staking.balanceOf(alice), 10 ether);
    }
}

contract StakingReadOnlyObserver {
    StakingRewards internal immutable staking;
    AdversarialERC20 internal immutable token;

    uint256 public observedTotalSupply;
    uint256 public observedAccountStake;
    uint256 public observedTokenBalance;

    constructor(StakingRewards staking_, AdversarialERC20 token_) {
        staking = staking_;
        token = token_;
    }

    function observe(address account) external {
        observedTotalSupply = staking.totalSupply();
        observedAccountStake = staking.balanceOf(account);
        observedTokenBalance = token.balanceOf(address(staking));
    }
}
