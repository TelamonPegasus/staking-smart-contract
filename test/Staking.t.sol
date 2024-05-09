// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Staking} from "../src/Staking.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract StakingBaseTest is Test {
    Staking public staking;

    address public alice = makeAddr("Aclice");
    address public bob = makeAddr("Bob");

    uint256 public REWARD_RATE_1Q;
    uint256 public REWARD_RATE_2Q;
    uint256 public REWARD_RATE_3Q;
    uint256 public REWARD_RATE_4Q;
    uint256 public DENOMINATOR;

    MockERC20 public stakeToken;
    MockERC20 public rewardToken;

    function setUp() public virtual {
        stakeToken = new MockERC20();
        rewardToken = new MockERC20();

        staking = new Staking(address(stakeToken), address(rewardToken));

        REWARD_RATE_1Q = staking.REWARD_RATE_1Q();
        REWARD_RATE_2Q = staking.REWARD_RATE_2Q();
        REWARD_RATE_3Q = staking.REWARD_RATE_3Q();
        REWARD_RATE_4Q = staking.REWARD_RATE_4Q();
        DENOMINATOR = staking.DENOMINATOR();
    }
}

contract StakingDisableTest is StakingBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_revertStakeBeforeEnable() public {
        assertEq(staking.stakingEnabled(), false);

        deal(address(stakeToken), alice, 100 ether);
        uint256 amount = 10 ether;
        uint256 durationInMonths = 12;
        
        vm.startPrank(alice);
        stakeToken.approve(address(staking), amount);
        vm.expectRevert("Staking is not enabled.");
        staking.stake(amount, durationInMonths);
        vm.stopPrank();

        assertEq(stakeToken.balanceOf(alice), 100 ether);
    }
}

contract StakingEnableTest is StakingBaseTest {
    function setUp() public override {
        super.setUp();

        staking.setStakingEnabled();
        deal(address(stakeToken), alice, 100 ether);
    }

    function test_stake(uint8 _amount, uint8 _durationInMonths) public {
        vm.assume(_amount <= 100 && _amount >= 1);
        vm.assume(_durationInMonths <= 60 && _durationInMonths >= 1);
        uint256 amount = uint256(_amount) * 1 ether;
        
        vm.startPrank(alice);
        stakeToken.approve(address(staking), amount);
        staking.stake(amount, _durationInMonths);
        vm.stopPrank();

        assertEq(stakeToken.balanceOf(alice), 100 ether - amount);

        (,,,uint256 rewards) = staking.getStakingInfo(alice, staking.numStakes(alice) - 1);
        assertEq(rewards, _calculateRewards(amount, _durationInMonths));

        assertEq(staking.totalSupply(), amount);
    }

    function test_stakeRevertZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert("cannot stake 0");
        staking.stake(0, 12);
        vm.stopPrank();
    }

    function test_stakeRevertInvalidDurationMonth(uint256 _durationInMonths) public {
        vm.assume(_durationInMonths > 60);

        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        vm.expectRevert("cannot stake for 0 days");
        staking.stake(1 ether, 0);

        vm.expectRevert("cannot stake for over 5 years");
        staking.stake(1 ether, _durationInMonths);
        vm.stopPrank();
    }

    function test_withdraw(uint8 _amount, uint8 _durationInMonths) public {
        vm.assume(_amount <= 100 && _amount >= 1);
        vm.assume(_durationInMonths <= 60 && _durationInMonths >= 1);
        uint256 amount = uint256(_amount) * 1 ether;
        
        vm.startPrank(alice);
        stakeToken.approve(address(staking), amount);
        staking.stake(amount, _durationInMonths);
        vm.stopPrank();

        (uint256 _currentAmount, uint256 lockOn, uint256 lockEnd, uint256 rewards) = staking.getStakingInfo(alice, 0);
        assertEq(amount, _currentAmount);
        assertEq(lockEnd, lockOn + uint256(_durationInMonths) * 30 days);
        vm.warp(lockEnd);

        vm.prank(alice);
        staking.withdraw(0);

        (uint256 leftAmount, , , uint256 leftRewards) = staking.getStakingInfo(alice, 0);
        assertEq(leftAmount, 0);
        assertEq(rewards, leftRewards);
    }

    function test_withdrawInvalidIndex() public {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether, 12);
        vm.stopPrank();

        vm.expectRevert("Invalid index of staking");
        vm.prank(alice);
        staking.withdraw(1);
    }

    function test_withdrawRemoveRewardsBeforeTimeisUp(uint8 _amount, uint8 _durationInMonths) public {
        vm.assume(_amount <= 100 && _amount >= 1);
        vm.assume(_durationInMonths <= 60 && _durationInMonths >= 1);
        uint256 amount = uint256(_amount) * 1 ether;
        
        vm.startPrank(alice);
        stakeToken.approve(address(staking), amount);
        staking.stake(amount, _durationInMonths);
        vm.stopPrank();

        (uint256 _currentAmount, uint256 lockOn, uint256 lockEnd, uint256 rewards) = staking.getStakingInfo(alice, 0);
        assertEq(amount, _currentAmount);
        assertEq(lockEnd, lockOn + uint256(_durationInMonths) * 30 days);
        assertEq(rewards, _calculateRewards(amount, _durationInMonths));

        vm.prank(alice);
        staking.withdraw(0);

        (, , , uint256 currentRewards) = staking.getStakingInfo(alice, 0);
        assertEq(currentRewards, 0);
    }

    function test_withdrawRevertZeroStakedAmount() public {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether, 12);
        vm.stopPrank();

        vm.expectRevert("Invalid index of staking");
        vm.prank(alice);
        staking.withdraw(1);
    }

    function test_claimRewards() public {

    }

    /***************************************
                    helper
    ***************************************/
    function _calculateRewards(uint256 _principal, uint256 _durationInMonths) private view returns (uint256) {
        if (_durationInMonths <= 3) {
            return _principal * REWARD_RATE_1Q / DENOMINATOR;
        } else if (_durationInMonths <= 6) {
            return _principal * REWARD_RATE_2Q / DENOMINATOR;
        } else if (_durationInMonths <= 9) {
            return _principal * REWARD_RATE_3Q / DENOMINATOR;
        } else {
            return _principal * REWARD_RATE_4Q / DENOMINATOR;
        }
    }
}
