// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Staking} from "../src/Staking.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingBaseTest is Test {
    Staking public staking;

    address public alice = makeAddr("Alice");

    uint256 public REWARD_RATE_1Q;
    uint256 public REWARD_RATE_2Q;
    uint256 public REWARD_RATE_3Q;
    uint256 public REWARD_RATE_4Q;
    uint256 public DENOMINATOR;

    MockERC20 public stakeToken;
    MockERC20 public rewardToken;

    using SafeERC20 for MockERC20;

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
        deal(address(rewardToken), address(staking), 1000 ether);
    }

    function test_stake(uint8 _amount, uint8 _durationInMonths) public {
        vm.assume(_amount <= 100 && _amount >= 1);
        vm.assume(
            _durationInMonths == 3 ||
            _durationInMonths == 6 ||
            _durationInMonths == 9 ||
            _durationInMonths == 12
        );
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
        vm.assume(
            _durationInMonths != 3 &&
            _durationInMonths != 6 &&
            _durationInMonths != 9 &&
            _durationInMonths != 12
        );

        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        // vm.expectRevert("cannot stake for 0 days");
        // staking.stake(1 ether, 0);

        vm.expectRevert("Invalid duration for staking.");
        staking.stake(1 ether, _durationInMonths);
        vm.stopPrank();
    }

    function test_withdraw(uint8 _amount, uint8 _durationInMonths) public {
        vm.assume(_amount <= 100 && _amount >= 1);
        vm.assume(
            _durationInMonths == 3 ||
            _durationInMonths == 6 ||
            _durationInMonths == 9 ||
            _durationInMonths == 12
        );
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
        vm.assume(
            _durationInMonths == 3 ||
            _durationInMonths == 6 ||
            _durationInMonths == 9 ||
            _durationInMonths == 12
        );
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

        vm.prank(alice);
        staking.withdraw(0);

        vm.expectRevert("There is no staked token");
        vm.prank(alice);
        staking.withdraw(0);
    }

    function test_claimRewards(uint8 _amount, uint8 _durationInMonths) public {
        vm.assume(_amount <= 100 && _amount >= 1);
        vm.assume(
            _durationInMonths == 3 ||
            _durationInMonths == 6 ||
            _durationInMonths == 9 ||
            _durationInMonths == 12
        );
        uint256 amount = uint256(_amount) * 1 ether;
        
        vm.startPrank(alice);
        stakeToken.approve(address(staking), amount);
        staking.stake(amount, _durationInMonths);
        vm.stopPrank();

        (, , uint256 lockEnd, uint256 rewards) = staking.getStakingInfo(alice, 0);
        assertEq(rewards, _calculateRewards(amount, _durationInMonths));
        assertEq(staking.totalSupply(), amount);

        vm.warp(lockEnd);
        vm.prank(alice);
        staking.claimRewards(0);

        (, , , uint256 leftRewards) = staking.getStakingInfo(alice, 0);
        assertEq(leftRewards, 0);

        assertEq(rewardToken.balanceOf(alice), rewards);
    }

    function test_claimRewardsRevertInvalidIndex() public {        
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether, 12);
        vm.stopPrank();

        vm.expectRevert("Invalid index of staking");
        vm.prank(alice);
        staking.claimRewards(1);
    }

    function test_claimRewardsRevertZeroRewards() public {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether, 12);
        vm.stopPrank();

        (, , uint256 lockEnd,) = staking.getStakingInfo(alice, 0);

        vm.warp(lockEnd);
        vm.prank(alice);
        staking.claimRewards(0);

        (, , , uint256 leftRewards) = staking.getStakingInfo(alice, 0);
        assertEq(leftRewards, 0);

        vm.expectRevert("There is no claimable reward token.");
        vm.prank(alice);
        staking.claimRewards(0);
    }

    function test_claimRewardsRevertBeforeTimeIsUp() public {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether, 3);
        vm.stopPrank();

        vm.expectRevert("Cannot claim rewards before locking is over.");
        vm.prank(alice);
        staking.claimRewards(0);
    }

    function test_withdrawAll() public {
        uint256 current = _stakeForTestBatchOperation();

        vm.warp(current + 4 * 30 days);
        assertFalse(staking.isStaked(alice, 0));
        assertTrue(staking.isStaked(alice, 1));

        uint256 aliceAmount = stakeToken.balanceOf(alice);
        uint256 totalSupply = staking.totalSupply();

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 amount_2, , ,) = staking.getStakingInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawAll(false);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakingInfo(alice, 1);

        assertEq(after_amount_1, 0);
        assertEq(after_amount_2, 0);
        assertEq(after_rewards_1, rewards_1);
        assertEq(after_rewards_2, 0);
        assertEq(stakeToken.balanceOf(alice), aliceAmount + amount_1 + amount_2);

        assertEq(staking.totalSupply(), 0);
    }

    function test_withdrawAllOnlyClaimable() public {
        uint256 current = _stakeForTestBatchOperation();

        vm.warp(current + 4 * 30 days);
        assertFalse(staking.isStaked(alice, 0));
        assertTrue(staking.isStaked(alice, 1));

        uint256 aliceAmount = stakeToken.balanceOf(alice);
        uint256 totalSupply = staking.totalSupply();

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 amount_2, , , uint256 rewards_2) = staking.getStakingInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawAll(true);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakingInfo(alice, 1);

        assertEq(after_amount_1, 0);
        assertEq(after_amount_2, amount_2);
        assertEq(after_rewards_1, rewards_1);
        assertEq(after_rewards_2, rewards_2);
        assertEq(stakeToken.balanceOf(alice), aliceAmount + amount_1);

        assertEq(staking.totalSupply(), amount_2);
    }

    function test_withdrawAllRevertNoStaking() public {
        vm.expectRevert("You didn't stake anything");
        vm.prank(alice);
        staking.withdrawAll(false);        
    }

    function test_withdrawBatch() public {
        uint256 current = _stakeForTestBatchOperation();

        vm.warp(current + 4 * 30 days);
        assertFalse(staking.isStaked(alice, 0));
        assertTrue(staking.isStaked(alice, 1));

        uint256 aliceAmount = stakeToken.balanceOf(alice);
        uint256 totalSupply = staking.totalSupply();

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 amount_2, , ,) = staking.getStakingInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawBatch(0, 1, false);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakingInfo(alice, 1);

        assertEq(after_amount_1, 0);
        assertEq(after_amount_2, 0);
        assertEq(after_rewards_1, rewards_1);
        assertEq(after_rewards_2, 0);
        assertEq(stakeToken.balanceOf(alice), aliceAmount + amount_1 + amount_2);

        assertEq(staking.totalSupply(), 0);
    }

    function test_withdrawBatchOnlyClaimable() public {
        uint256 current = _stakeForTestBatchOperation();

        vm.warp(current + 4 * 30 days);
        assertFalse(staking.isStaked(alice, 0));
        assertTrue(staking.isStaked(alice, 1));

        uint256 aliceAmount = stakeToken.balanceOf(alice);
        uint256 totalSupply = staking.totalSupply();

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 amount_2, , , uint256 rewards_2) = staking.getStakingInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawBatch(0, 1, true);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakingInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakingInfo(alice, 1);

        assertEq(after_amount_1, 0);
        assertEq(after_amount_2, amount_2);
        assertEq(after_rewards_1, rewards_1);
        assertEq(after_rewards_2, rewards_2);
        assertEq(stakeToken.balanceOf(alice), aliceAmount + amount_1);

        assertEq(staking.totalSupply(), amount_2);
    }

    function test_withdrawBatchRevertNoStaking() public {
        vm.expectRevert("You didn't stake anything");
        vm.prank(alice);
        staking.withdrawBatch(0, 0, false);
    }

    function test_withdrawBatchRevertInvalidIndex() public {
        _stakeForTestBatchOperation();

        vm.expectRevert("Invalid indexes.");
        vm.prank(alice);
        staking.withdrawBatch(1, 0, false);
    }

    function test_withdrawBatchRevertInvalidToIndex() public {
        _stakeForTestBatchOperation();

        vm.expectRevert("Index cannot be over the length of staking");
        vm.prank(alice);
        staking.withdrawBatch(0, 2, false);
    }

    function test_receoverERC20() public {
        MockERC20 thirdToken = new MockERC20();
        deal(address(thirdToken), alice, 1 ether);

        vm.prank(alice);
        thirdToken.transfer(address(staking), 1 ether);

        assertEq(thirdToken.balanceOf(alice), 0);
        assertEq(thirdToken.balanceOf(address(staking)), 1 ether);

        staking.recoverERC20(address(thirdToken), 1 ether);
        assertEq(thirdToken.balanceOf(address(this)), 1 ether);
    }

    function test_receoverERC20RevertStakeToken() public {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether, 3);
        vm.stopPrank();

        vm.expectRevert("cannot withdraw the staking token");
        staking.recoverERC20(address(stakeToken), 1 ether);
    }

    function test_isStakedRevertInvalidIndex() public {
        vm.expectRevert("Invalid index for staked records.");
        staking.isStaked(alice, 0);
    }

    function test_getStakingInfoRevertInvalidIndex() public {
        vm.expectRevert("Invalid index for staked records.");
        staking.getStakingInfo(alice, 0);
    }

    function test_setStakingEnabledRevertAgain() public {
        assertTrue(staking.stakingEnabled());
        vm.expectRevert("Staking is already enabled");
        staking.setStakingEnabled();
    }

    function test_setStakeToken() public {
        MockERC20 thirdToken = new MockERC20();
        staking.setToken(address(thirdToken));
        assertEq(address(staking.token()), address(thirdToken));
    }

    function test_setStakeTokenRevertZeroAddress() public {
        vm.expectRevert("Stake token address cannot be zero address");
        staking.setToken(address(0));
    }

    function test_setRewardToken() public {
        MockERC20 thirdToken = new MockERC20();
        staking.setRewardToken(address(thirdToken));
        assertEq(address(staking.rewardToken()), address(thirdToken));
    }

    function test_setRewardTokenRevertZeroAddress() public {
        vm.expectRevert("Reward token address cannot be zero address");
        staking.setRewardToken(address(0));
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

    function _stakeForTestBatchOperation() private returns(uint256) {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 60 ether);
        staking.stake(40 ether, 6);

        (, uint256 lockOn, , ) = staking.getStakingInfo(alice, 0);
        // 2 months later
        uint256 current = lockOn + 2 * 30 days;
        vm.warp(current);

        staking.stake(20 ether, 9);
        vm.stopPrank();

        return current;
    }
}
