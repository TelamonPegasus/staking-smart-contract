// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Staking} from "../src/Staking.sol";
import {Claiming} from "../src/Claiming.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BaseTest is Test {
    Staking public staking;
    Claiming public claiming;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    uint256 public REWARD_RATE_1Q;
    uint256 public REWARD_RATE_2Q;
    uint256 public REWARD_RATE_3Q;
    uint256 public REWARD_RATE_4Q;
    uint256 public DENOMINATOR;

    MockERC20 public stakeToken;

    using SafeERC20 for MockERC20;

    function setUp() public virtual {
        stakeToken = new MockERC20();

        staking = new Staking(address(stakeToken));
        claiming = new Claiming(address(stakeToken));

        REWARD_RATE_1Q = staking.REWARD_RATE_1Q();
        REWARD_RATE_2Q = staking.REWARD_RATE_2Q();
        REWARD_RATE_3Q = staking.REWARD_RATE_3Q();
        REWARD_RATE_4Q = staking.REWARD_RATE_4Q();
        DENOMINATOR = staking.DENOMINATOR();
    }
}

contract ClaimingBaseTest is BaseTest {
    function setUp() public override {
        super.setUp();

        claiming.setClaimStart(block.timestamp + 5 days);
    }

    function test_setTokenRevertZeroAddress() public {
        vm.expectRevert("Token address cannot be zero.");
        claiming.setToken(address(0));
    }

    function test_setToken() public {
        MockERC20 newMockERC20 = new MockERC20();

        claiming.setToken(address(newMockERC20));
        assertEq(address(claiming.token()), address(newMockERC20));
    }

    function test_setStakingRevertZeroAddress() public {
        vm.expectRevert("Staking contract cannot be zero address.");
        claiming.setStakingContract(address(0));
    }

    function test_setStaking() public {
        claiming.setStakingContract(address(staking));
        assertEq(claiming.staking(), address(staking));
    }

    function test_setClaimStartRevertInvalid() public {
        vm.expectRevert("Invalid time for start claiming.");
        claiming.setClaimStart(0);
    }

    function test_setClaimStart(uint8 startDay) public {
        vm.assume(startDay > 0);
        uint256 startTime = uint256(startDay) * 1 days;
        claiming.setClaimStart(block.timestamp + startTime);
        assertGt(claiming.claimStart(), block.timestamp);
    }

    function test_setClaimRevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        claiming.setClaim(alice, 1 ether);
    }

    function test_setClaimRevertZeroAddress() public {
        vm.expectRevert("User address cannot be zero.");
        claiming.setClaim(address(0), 1 ether);
    }

    function test_setClaim() public {
        claiming.setClaim(alice, 1 ether);

        uint256 index = claiming.getClaimInfoIndex(alice);
        assertEq(index, 1);
        uint256 amount = claiming.getClaimableAmount(alice);
        assertEq(amount, 1 ether);

        claiming.setClaim(alice, 2 ether);

        index = claiming.getClaimInfoIndex(alice);
        assertEq(index, 1);
        amount = claiming.getClaimableAmount(alice);
        assertEq(amount, 2 ether);

    }

    function test_setClaimBatchRevertZeroArray() public {
        address[] memory users = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert("Invalid input array's length.");
        claiming.setClaimBatch(users, amounts);
    }

    function test_setClaimBatchRevertWrongMaxLength() public {
        address[] memory users = new address[](claiming.MAX_BATCH_SET_CLAIM() + 1);
        uint256[] memory amounts = new uint256[](claiming.MAX_BATCH_SET_CLAIM() + 1);

        vm.expectRevert("Invalid input array's length.");
        claiming.setClaimBatch(users, amounts);
    }

    function test_setClaimBatchRevertWrongLength() public {
        address[] memory users = new address[](10);
        uint256[] memory amounts = new uint256[](11);

        vm.expectRevert("The length of arrays for users and amounts should be same.");
        claiming.setClaimBatch(users, amounts);
    }

    function test_setClaimBatch() public {
        address[] memory users = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        users[0] = alice;
        users[1] = bob;
        users[2] = alice; // test for overwriting previous info
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 1.5 ether;

        claiming.setClaimBatch(users, amounts);
        assertEq(claiming.getClaimInfoIndex(alice), 1);
        assertEq(claiming.getClaimInfoIndex(bob), 2);
        assertEq(claiming.getClaimableAmount(alice), 1.5 ether);
        assertEq(claiming.getClaimableAmount(bob), 2 ether);
    }

    function test_setDepositRevertZeroAmount() public {
        vm.expectRevert("Cannot deposit zero amount");
        claiming.deposit(0);
    }

    function test_withdrawRevertZeroAmount() public {
        vm.expectRevert("Cannot withdraw zero amount");
        claiming.withdraw(0);
    }

    function test_depositAndWithdraw() public {
        deal(address(stakeToken), address(this), 200 ether);
        stakeToken.approve(address(claiming), 100 ether);
        claiming.deposit(100 ether);

        assertEq(claiming.getTotalDeposits(), 100 ether);

        claiming.withdraw(40 ether);
        assertEq(claiming.getTotalDeposits(), 60 ether);
        assertEq(stakeToken.balanceOf(address(this)), 140 ether);
    }

    function test_claimRevertBeforeClaimStart() public {
        deal(address(stakeToken), address(this), 200 ether);
        stakeToken.approve(address(claiming), 100 ether);
        claiming.deposit(100 ether);

        claiming.setClaim(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert("Claiming is not able now.");
        claiming.claim(alice, 0.5 ether);
    }
}

contract ClaimingTest is BaseTest {
    function setUp() public override {
        super.setUp();

        claiming.setClaimStart(block.timestamp + 5 days);

        deal(address(stakeToken), address(this), 200 ether);
        stakeToken.approve(address(claiming), 200 ether);
        claiming.deposit(200 ether);
        claiming.setClaim(alice, 5 ether);
        claiming.setClaim(bob, 2 ether);

        vm.warp(block.timestamp + 6 days);
    }

    function test_getClaimInfoLength() public view {
        assertEq(claiming.getClaimInfoLength(), 2);
    }

    function test_getClaimInfoRevertZeroIndex() public {
        vm.expectRevert("Invalid start index");
        claiming.getClaimInfo(0);
    }

    function test_getClaimInfoRevertInvalidIndex(uint256 index) public {
        vm.assume(index > 2);
        vm.expectRevert();
        claiming.getClaimInfo(index);
    }

    function test_getClaimInfoArrayRevertZeroFromIndex() public {
        vm.expectRevert("Invalid start index");
        claiming.getClaimInfoArray(0, 1);
    }

    function test_getClaimInfoArrayInvalidIndexes() public {
        vm.expectRevert("Invalid indexes.");
        claiming.getClaimInfoArray(1, 0);
    }

    function test_getClaimInfoArrayInvalidToIndex() public {
        vm.expectRevert("Index cannot be over the length of staking");
        claiming.getClaimInfoArray(1, 3);
    }

    function test_getClaimInfoArray() public view {
        Claiming.ClaimInfo[] memory claimInfoArray = new Claiming.ClaimInfo[](2);
        claimInfoArray = claiming.getClaimInfoArray(1, 2);
        assertEq(claimInfoArray[0].user, alice);
        assertEq(claimInfoArray[1].user, bob);
        assertEq(claimInfoArray[0].amount, 5 ether);
        assertEq(claimInfoArray[1].amount, 2 ether);
    }

    function test_claimRevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Cannot claim zero amount");
        claiming.claim(alice, 0);
    }

    function test_claimRevertZeroAddressDestination() public {
        vm.prank(alice);
        vm.expectRevert("Cannot claim to zero address");
        claiming.claim(address(0), 1 ether);
    }

    function test_claimRevertInsufficientAmount() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient claimable amount");
        claiming.claim(alice, 5.1 ether);
    }

    function test_claim() public {
        vm.startPrank(alice);
        claiming.claim(alice, 1 ether);
        claiming.claim(bob, 2 ether);
        vm.stopPrank();

        vm.prank(bob);
        claiming.claim(bob, 1.5 ether);

        assertEq(claiming.getClaimableAmount(alice), 2 ether);
        assertEq(claiming.getClaimableAmount(bob), 0.5 ether);

        assertEq(stakeToken.balanceOf(alice), 1 ether);
        assertEq(stakeToken.balanceOf(bob), 3.5 ether);
        assertEq(stakeToken.balanceOf(address(claiming)), 195.5 ether);
    }

    function test_stakeRevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Cannot claim zero amount");
        claiming.stake(0, 3);
    }

    function test_stakeRevertStakingContractZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert("Invalid staking address");
        claiming.stake(1 ether, 3);
    }

    function test_stakeRevertNotFromClaiming() public {
        claiming.setStakingContract(address(staking));
        vm.prank(alice);
        vm.expectRevert("Only claiming contract can call this function");
        claiming.stake(1 ether, 3);
    }
}

contract StakeFromClaimingTest is BaseTest {
    function setUp() public override {
        super.setUp();

        staking.setClaimingContract(address(claiming));
        claiming.setStakingContract(address(staking));
        claiming.setClaimStart(block.timestamp + 5 days);

        deal(address(stakeToken), address(this), 200 ether);
        stakeToken.approve(address(claiming), 200 ether);
        claiming.deposit(200 ether);
        claiming.setClaim(alice, 5 ether);
        claiming.setClaim(bob, 2 ether);

        vm.warp(block.timestamp + 6 days);
    }

    function test_stakeRevertInsufficientClaimableAmount() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient claimable amount");
        claiming.stake(5.1 ether, 3);
    }

    function test_stakeRevertInvalidDurationInMonth(uint256 _durationInMonths) public {
        vm.assume(
            _durationInMonths != 3 &&
            _durationInMonths != 6 &&
            _durationInMonths != 9 &&
            _durationInMonths != 12
        );

        vm.prank(alice);
        vm.expectRevert("Invalid duration for staking.");
        claiming.stake(1 ether, _durationInMonths);
    }

    function test_stakeFromClaiming(uint8 _durationInMonths) public {
        vm.assume(
            _durationInMonths == 3 ||
            _durationInMonths == 6 ||
            _durationInMonths == 9 ||
            _durationInMonths == 12
        );
        
        vm.prank(alice);
        claiming.stake(2 ether, _durationInMonths);

        assertEq(stakeToken.balanceOf(address(staking)), 2 ether);
        assertEq(stakeToken.balanceOf(address(claiming)), 198 ether);
        assertEq(claiming.getClaimableAmount(alice), 3 ether);

        (,,,uint256 rewards) = staking.getStakeInfo(alice, staking.numStakes(alice) - 1);
        assertEq(rewards, _calculateRewards(2 ether, _durationInMonths));

        assertEq(staking.totalSupply(), 2 ether);
    }

    /***************************************
                    helper
    ***************************************/
    function _calculateRewards(uint256 _principal, uint256 _durationInMonths) private view returns (uint256) {
        if (_durationInMonths <= 3) {
            return _principal * REWARD_RATE_1Q * _durationInMonths / (12 * DENOMINATOR);
        } else if (_durationInMonths <= 6) {
            return _principal * REWARD_RATE_2Q * _durationInMonths / (12 * DENOMINATOR);
        } else if (_durationInMonths <= 9) {
            return _principal * REWARD_RATE_3Q * _durationInMonths / (12 * DENOMINATOR);
        } else {
            return _principal * REWARD_RATE_4Q * _durationInMonths / (12 * DENOMINATOR);
        }
    }
}

contract StakingDisableTest is BaseTest {
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

contract StakingEnableTest is BaseTest {
    function setUp() public override {
        super.setUp();

        staking.setStakingEnabled();
        deal(address(stakeToken), alice, 1000 ether);
        // deal(address(rewardToken), address(staking), 1000 ether);
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

        assertEq(stakeToken.balanceOf(alice), 1000 ether - amount);

        (,,,uint256 rewards) = staking.getStakeInfo(alice, staking.numStakes(alice) - 1);
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

        (uint256 _currentAmount, uint256 lockOn, uint256 lockEnd, uint256 rewards) = staking.getStakeInfo(alice, 0);
        assertEq(amount, _currentAmount);
        assertEq(lockEnd, lockOn + uint256(_durationInMonths) * 30 days);
        vm.warp(lockEnd);

        vm.prank(alice);
        staking.withdraw(0);

        (uint256 leftAmount, , , uint256 leftRewards) = staking.getStakeInfo(alice, 0);
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

        (uint256 _currentAmount, uint256 lockOn, uint256 lockEnd, uint256 rewards) = staking.getStakeInfo(alice, 0);
        assertEq(amount, _currentAmount);
        assertEq(lockEnd, lockOn + uint256(_durationInMonths) * 30 days);
        assertEq(rewards, _calculateRewards(amount, _durationInMonths));

        vm.prank(alice);
        staking.withdraw(0);

        (, , , uint256 currentRewards) = staking.getStakeInfo(alice, 0);
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

        (, , uint256 lockEnd, uint256 rewards) = staking.getStakeInfo(alice, 0);
        assertEq(rewards, _calculateRewards(amount, _durationInMonths));
        assertEq(staking.totalSupply(), amount);

        uint256 balanceBeforeRewards = stakeToken.balanceOf(alice);
        vm.warp(lockEnd);
        vm.prank(alice);
        staking.claimRewards(0);

        (, , , uint256 leftRewards) = staking.getStakeInfo(alice, 0);
        assertEq(leftRewards, 0);

        assertEq(stakeToken.balanceOf(alice), balanceBeforeRewards + rewards);
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

        (, , uint256 lockEnd,) = staking.getStakeInfo(alice, 0);

        vm.warp(lockEnd);
        vm.prank(alice);
        staking.claimRewards(0);

        (, , , uint256 leftRewards) = staking.getStakeInfo(alice, 0);
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

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 amount_2, , ,) = staking.getStakeInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawAll(false);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakeInfo(alice, 1);

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

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 amount_2, , , uint256 rewards_2) = staking.getStakeInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawAll(true);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakeInfo(alice, 1);

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

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 amount_2, , ,) = staking.getStakeInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawBatch(0, 1, false);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakeInfo(alice, 1);

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

        (uint256 amount_1, , , uint256 rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 amount_2, , , uint256 rewards_2) = staking.getStakeInfo(alice, 1);

        assertEq(totalSupply, amount_1 + amount_2);

        vm.prank(alice);
        staking.withdrawBatch(0, 1, true);

        (uint256 after_amount_1, , , uint256 after_rewards_1) = staking.getStakeInfo(alice, 0);
        (uint256 after_amount_2, , , uint256 after_rewards_2) = staking.getStakeInfo(alice, 1);

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
        staking.getStakeInfo(alice, 0);
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

    /***************************************
                    helper
    ***************************************/
    function _calculateRewards(uint256 _principal, uint256 _durationInMonths) private view returns (uint256) {
        if (_durationInMonths <= 3) {
            return _principal * REWARD_RATE_1Q * _durationInMonths / (12 * DENOMINATOR);
        } else if (_durationInMonths <= 6) {
            return _principal * REWARD_RATE_2Q * _durationInMonths / (12 * DENOMINATOR);
        } else if (_durationInMonths <= 9) {
            return _principal * REWARD_RATE_3Q * _durationInMonths / (12 * DENOMINATOR);
        } else {
            return _principal * REWARD_RATE_4Q * _durationInMonths / (12 * DENOMINATOR);
        }
    }

    function _stakeForTestBatchOperation() private returns(uint256) {
        vm.startPrank(alice);
        stakeToken.approve(address(staking), 60 ether);
        staking.stake(40 ether, 6);

        (, uint256 lockOn, , ) = staking.getStakeInfo(alice, 0);
        // 2 months later
        uint256 current = lockOn + 2 * 30 days;
        vm.warp(current);

        staking.stake(20 ether, 9);
        vm.stopPrank();

        return current;
    }
}
