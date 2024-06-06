// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMining} from "../src/LiquidityMining.sol";
import {Claiming} from "../src/Claiming.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import "../src/interfaces/IUniswapV2Factory.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "../src/interfaces/IUniswapV2Pair.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BaseTest is Test {
    uint256 public mainnetFork;

    LiquidityMining public liquidityMining;
    Claiming public claiming;
    MockERC20 public token;
    
    address public priceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");

    function setUp() public virtual {
        mainnetFork = vm.createSelectFork("mainnet");

        token = new MockERC20();

        liquidityMining = new LiquidityMining(address(token), priceFeed);
    }
}

contract SetterTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_setTokenRevertZeroAddress() public {
        vm.expectRevert("Token address cannot be zero.");

        liquidityMining.setToken(address(0));
    }

    function test_setToken() public {
        MockERC20 newMockERC20 = new MockERC20();

        liquidityMining.setToken(address(newMockERC20));
        assertEq(address(liquidityMining.token()), address(newMockERC20));
    }

    function test_setWETHRevertZeroAddress() public {
        vm.expectRevert("Token address cannot be zero.");

        liquidityMining.setWETH(address(0));
    }

    function test_setWETH() public {
        MockERC20 newMockERC20 = new MockERC20();

        liquidityMining.setWETH(address(newMockERC20));
        assertEq(address(liquidityMining.WETH()), address(newMockERC20));
    }

    function test_setDepositRevertInvalidStartTime(uint16 diff) public {
        vm.assume(diff != 0);
        uint256 startTime = block.timestamp - uint256(diff);

        vm.expectRevert("Invalid time for start deposit.");
        liquidityMining.setDepositStart(startTime);
    }

    function test_setDepositStart(uint16 diff) public {
        uint256 startTime = block.timestamp + diff;
        liquidityMining.setDepositStart(startTime);
        assertEq(liquidityMining.depositStart(), startTime);
    }

    function test_setClaimingContractRevertZeroAddress() public {
        vm.expectRevert("Contract address cannot be zero address");

        liquidityMining.setClaimingContract(address(0));
    }

    function test_setClaimingContract() public {
        claiming = new Claiming(address(token));

        liquidityMining.setClaimingContract(address(claiming));
        assertEq(liquidityMining.claiming(), address(claiming));
    }

    function test_setAllowedMinimumDeposit(uint256 _amount) public {
        liquidityMining.setAllowedMinimumDeposit(_amount);
        assertEq(liquidityMining.ALLOWED_MINIMUM_DEPOSIT(), _amount);
    }

    function test_setPairRevertZeroAddress() public {
        vm.expectRevert("Pair address cannot be zero");

        liquidityMining.setPair(address(0));
    }

    function test_setPair(address _pair) public {
        vm.assume(_pair != address(0));

        liquidityMining.setPair(_pair);
    }

    function test_depositETHRevertInvalidStartTime() public {
        deal(alice, 10 ether);

        // revert for zero deposit start time
        vm.expectRevert("Deposit is not allowed for now");
        vm.prank(alice);
        liquidityMining.depositETH{value: 1 ether}();

        // revert for not reached at start time
        liquidityMining.setDepositStart(block.timestamp + 1 days);
        vm.expectRevert("Deposit is not allowed for now");
        vm.prank(alice);
        liquidityMining.depositETH{value: 1 ether}();
    }

    // states for liquidity reward
    function test_setRewardStatesRevertWhenZeroDepositStart() public {
        vm.expectRevert("Deposit start time should be set");
        liquidityMining.setRewardStates(block.timestamp, 70, 700 ether);
    }

    function test_setRewardStatesRevertInvalidValue(uint16 diff) public {
        vm.assume(diff > 0);

        uint256 depositStart = block.timestamp;
        liquidityMining.setDepositStart(depositStart);

        vm.expectRevert("Invalid reward start time");
        liquidityMining.setRewardStates(0, 70, 700 ether);

        vm.expectRevert("Cannot be before deposit start time");
        liquidityMining.setRewardStates(block.timestamp - diff, 70, 700 ether);
        
        vm.expectRevert("Invalid reward period");
        liquidityMining.setRewardStates(block.timestamp, 0, 700 ether);

        vm.expectRevert("Invalid reward token amount");
        liquidityMining.setRewardStates(block.timestamp, 70, 0);
    }
}

contract DepositTest is BaseTest {
    function setUp() public override {
        super.setUp();

        liquidityMining.setDepositStart(block.timestamp);

        claiming = new Claiming(address(token));
        claiming.setLiquidityMiningContract(address(liquidityMining));
        liquidityMining.setClaimingContract(address(claiming));

        deal(address(token), address(claiming), 1000000 ether);
        deal(alice, 10 ether);
        deal(bob, 10 ether);
        claiming.setClaim(alice, 5000 ether); // 5000 USD
        claiming.setClaim(bob, 3000 ether); // 3000 USD
    }

    function test_depositETHRevertZeroETH() public {
        vm.expectRevert("Cannot deposit 0 ETH");
        vm.prank(alice);
        liquidityMining.depositETH();
    }

    function test_depositETHRevertAllowedMinimumDeposit() public {
        liquidityMining.setAllowedMinimumDeposit(5 ether);

        vm.expectRevert("Insufficient deposit amount for minimum allowed");
        vm.prank(alice);
        liquidityMining.depositETH{value: 1 ether}();
    }

    function test_depositETHInsufficientClaimableToken() public {
        vm.expectRevert("You don't have sufficient claimable token amount to deposit ETH");

        vm.prank(alice);
        liquidityMining.depositETH{value: 2 ether}(); // about 7000 USD
    }

    function test_depositETHInvalidPermissionToSetClaim() public {
         // any address except liquidity mining
        claiming.setLiquidityMiningContract(address(this));

        vm.expectRevert("Invalid permission to call this function");
        vm.prank(alice);
        liquidityMining.depositETH{value: 1 ether}();
    }

    function test_depositETH() public {
        uint256 originalClaimableAmount = claiming.getClaimableAmount(alice);

        vm.prank(alice);
        liquidityMining.depositETH{value: 1 ether}(); // about 4000 USD

        uint256 claimableAmount = claiming.getClaimableAmount(alice);
        (uint256 price, uint256 decimals) = liquidityMining.fetchETHUSDPrice();
        assertEq(originalClaimableAmount - claimableAmount, price * 1 ether / 10 ** decimals);

        (uint256 amount, ,) = liquidityMining.getUserDepositInfo(alice, 0);
        assertEq(amount, 1 ether);
        assertEq(liquidityMining.getUserTotalDeposit(alice), 1 ether);
        assertEq(liquidityMining.totalDeposits(), 1 ether);
    }

    function test_depositETHComplex() public {
        vm.prank(alice);
        liquidityMining.depositETH{value: 1 ether}();
        
        (uint256 amount, ,) = liquidityMining.getUserDepositInfo(alice, 0);
        assertEq(amount, 1 ether);
        assertEq(liquidityMining.getUserTotalDeposit(alice), 1 ether);
        assertEq(liquidityMining.totalDeposits(), 1 ether);
        assertEq(address(liquidityMining).balance, 1 ether);

        vm.prank(bob);
        liquidityMining.depositETH{value: 0.5 ether}();

        (amount, ,) = liquidityMining.getUserDepositInfo(bob, 0);
        assertEq(amount, 0.5 ether);
        assertEq(liquidityMining.getUserTotalDeposit(bob), 0.5 ether);
        assertEq(liquidityMining.totalDeposits(), 1.5 ether);
        assertEq(address(liquidityMining).balance, 1.5 ether);

        vm.prank(alice);
        liquidityMining.depositETH{value: 0.2 ether}();
        
        (amount, ,) = liquidityMining.getUserDepositInfo(alice, 1);
        assertEq(amount, 0.2 ether);
        assertEq(liquidityMining.getUserTotalDeposit(alice), 1.2 ether);
        assertEq(liquidityMining.totalDeposits(), 1.7 ether);
        assertEq(address(liquidityMining).balance, 1.7 ether);
    }
}

contract LiquidityBaseTest is BaseTest {
    IUniswapV2Pair public pair;
    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Factory public uniswapFactory;

    function setUp() public override virtual {
        super.setUp();

        liquidityMining.setDepositStart(block.timestamp);

        claiming = new Claiming(address(token));
        claiming.setLiquidityMiningContract(address(liquidityMining));
        claiming.setClaimStart(block.timestamp + 14 days);
        liquidityMining.setClaimingContract(address(claiming));

        deal(address(token), address(claiming), 1000000 ether);
        deal(alice, 10 ether);
        deal(bob, 10 ether);
        claiming.setClaim(alice, 15000 ether); // 15000 USD
        claiming.setClaim(bob, 10000 ether); // 10000 USD

        // add initial liquidity with ETH of 200K USD worth
        uniswapRouter = liquidityMining.uniswapV2Router();
        uniswapFactory = liquidityMining.uniswapV2Factory();

        (uint256 ethPrice, uint256 decimals) = liquidityMining.fetchETHUSDPrice();
        uint256 ethAmount = 2000000 * (10 ** decimals) / ethPrice * 1 ether;
        deal(address(this), ethAmount);
        deal(address(token), address(this), 2000000 ether);
        token.approve(address(uniswapRouter), 2000000 ether);
        uniswapRouter.addLiquidityETH{value: ethAmount}(
            address(token),
            2000000 ether,
            100,
            100,
            address(this),
            block.timestamp
        );

        pair = IUniswapV2Pair(uniswapFactory.getPair(address(token), liquidityMining.WETH()));
    }

    function _depositETH() internal {
        vm.prank(alice);
        liquidityMining.depositETH{value: 2 ether}(); // about 7500 USD
        vm.prank(bob);
        liquidityMining.depositETH{value: 1 ether}(); // under 4000 USD
        vm.prank(alice);
        liquidityMining.depositETH{value: 0.5 ether}(); // under 2000 USD
        assertEq(liquidityMining.totalDeposits(), 3.5 ether);
        assertEq(address(liquidityMining).balance, 3.5 ether);

        vm.warp(block.timestamp + 14 days); // 2 weeks later
    }
}

contract LiquidityTest is LiquidityBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_listLiquidityRevertZeroDeposits() public {
        vm.expectRevert("Insufficient ETH balance to mint LP");
        liquidityMining.listLiquidity(address(pair));
    }

    function test_listLiquidity() public {
        _depositETH();
        deal(address(token), address(claiming), 1000000 ether);

        uint256 amount;
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        if (address(token) < liquidityMining.WETH()) {
            amount = uniswapRouter.quote(liquidityMining.totalDeposits(), reserve1, reserve0);
        } else {
            amount = uniswapRouter.quote(liquidityMining.totalDeposits(), reserve0, reserve1);
        }
        console.log("Sale token was transferred from claiming: ", amount / 1 ether);

        liquidityMining.listLiquidity(address(pair));
        console.log("Minted liquidity: ", liquidityMining.listedLiquidity() / 1 ether);

        // revert when add liquidity again
        vm.expectRevert("Liquidity was already listed");
        liquidityMining.listLiquidity(address(pair));

        // revert when deposit ETH after listing
        vm.expectRevert("Liquidity was already listed");
        vm.prank(alice);
        liquidityMining.depositETH{value: 0.5 ether}();
    }

    function test_removeLiquidityRevertBeforeListing() public {
        _depositETH();
        liquidityMining.listLiquidity(address(pair));
        vm.expectRevert("Cannot remove liquidity until 7 days after listing");
        vm.prank(alice);
        liquidityMining.removeLiquidity(0);
    }

    function test_removeLiquidityRevertInvalidTimeAndIndex() public {
        _depositETH();
        deal(address(token), address(claiming), 1000000 ether);

        liquidityMining.listLiquidity(address(pair));
        
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Cannot remove liquidity until 7 days after listing");
        vm.prank(alice);
        liquidityMining.removeLiquidity(0);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("Invalid index value");
        vm.prank(alice);
        liquidityMining.removeLiquidity(2);
    }

    function test_removeLiquidity() public {
        _depositETH();
        deal(address(token), address(claiming), 1000000 ether);

        liquidityMining.listLiquidity(address(pair));
        
        vm.warp(block.timestamp + 7 days);

        uint256 originalETH = address(alice).balance;
        uint256 originalToken = token.balanceOf(alice);
        uint256 originalLiquidity = pair.balanceOf(address(liquidityMining));
        assertEq(originalLiquidity, liquidityMining.listedLiquidity());

        vm.prank(alice);
        liquidityMining.removeLiquidity(0);

        uint256 currentETH = address(alice).balance;
        uint256 currentToken = token.balanceOf(alice);
        uint256 currentLiquidity = pair.balanceOf(address(liquidityMining));
        console.log("Received ETH: ", (currentETH - originalETH) / 1 ether);
        console.log("Received Token: ", (currentToken - originalToken) / 1 ether);
        console.log("Removed liquidity: ", (originalLiquidity - currentLiquidity) / 1 ether);

        ( , , bool removed ) = liquidityMining.getUserDepositInfo(alice, 0);
        assertEq(removed, true);

        // revert when try to remove liquidity again
        vm.expectRevert("This liquidity was already removed");
        vm.prank(alice);
        liquidityMining.removeLiquidity(0);
    }
}

contract LiquidityRewardTest is LiquidityBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_simpleSetRewardStates() public {
        liquidityMining.setRewardStates(block.timestamp, 35, 3500 ether);
        uint256 startDay = liquidityMining.startDay();
        assertEq(startDay, block.timestamp / 1 days);
        (uint256 amount, ,) = liquidityMining.getTotalDailyCheckpoint(startDay);
        assertEq(amount, 0);
        assertEq(35, liquidityMining.rewardPeriod());
        assertEq(3500 ether, liquidityMining.totalReward());
    }

    function test_depositCheckpoint() public {
        uint256 depositStartDay = liquidityMining.depositStart() / 1 days;

        // 1st day - alice deposits 2 ether
        vm.prank(alice);
        liquidityMining.depositETH{value: 2 ether}(); // about 7500 USD
        (uint256 amount, uint256 prev, uint256 next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay);
        assertEq(amount, 2 ether);
        assertEq(prev, 0);
        assertEq(next, 0);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay);
        assertEq(amount, 2 ether);
        assertEq(prev, 0);
        assertEq(next, 0);

        // 2nd day - bob deposits 1 ether
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        liquidityMining.depositETH{value: 1 ether}(); // under 4000 USD
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(bob, depositStartDay + 1);
        assertEq(amount, 1 ether);
        assertEq(prev, 0);
        assertEq(next, 0);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 1);
        assertEq(amount, 3 ether);
        assertEq(prev, depositStartDay);
        assertEq(next, 0);

        // 4th day - alice deposits 0.5 ether again
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        liquidityMining.depositETH{value: 0.5 ether}(); // under 2000 USD
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 3);
        assertEq(amount, 2.5 ether);
        assertEq(prev, depositStartDay);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay);
        assertEq(next, depositStartDay + 3);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 3);
        assertEq(amount, 3.5 ether);
        assertEq(prev, depositStartDay + 1);
        assertEq(next, 0);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 1);
        assertEq(amount, 3 ether);
        assertEq(prev, depositStartDay);
        assertEq(next, depositStartDay + 3);

        // 2 weeks later, list liquidity
        vm.warp(block.timestamp + 11 days);
        deal(address(token), address(claiming), 1000000 ether);
        liquidityMining.listLiquidity(address(pair));

        vm.expectRevert("Invalid ETH deposit");
        vm.prank(alice);
        liquidityMining.addLiquidity(2000 ether);

        vm.expectRevert("Invalid token deposit");
        vm.prank(alice);
        liquidityMining.addLiquidity{value: 0.5 ether}(0);

        // 15th day, alice adds liquidity with 0.5 eth & some tokens
        vm.startPrank(alice);
        claiming.claim(alice, 2000 ether);
        token.approve(address(liquidityMining), 2000 ether);
        liquidityMining.addLiquidity{value: 0.5 ether}(2000 ether);
        vm.stopPrank();
        // checking history
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 14);
        assertEq(amount, 3 ether);
        assertEq(prev, depositStartDay + 3);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 3);
        assertEq(next, depositStartDay + 14);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 14);
        assertEq(amount, 4 ether);
        assertEq(prev, depositStartDay + 3);
        assertEq(next, 0);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 3);
        assertEq(amount, 3.5 ether);
        assertEq(prev, depositStartDay + 1);
        assertEq(next, depositStartDay + 14);

        // 18th day, bob adds liquidity with 1 eth & some tokens
        vm.warp(block.timestamp + 3 days);
        vm.startPrank(bob);
        claiming.claim(bob, 4000 ether);
        token.approve(address(liquidityMining), 4000 ether);
        liquidityMining.addLiquidity{value: 1 ether}(4000 ether);
        vm.stopPrank();
        // checking history
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(bob, depositStartDay + 17);
        assertEq(amount, 2 ether);
        assertEq(prev, depositStartDay + 1);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getUserDailyCheckpoint(bob, depositStartDay + 1);
        assertEq(next, depositStartDay + 17);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 17);
        assertEq(amount, 5 ether);
        assertEq(prev, depositStartDay + 14);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 14);
        assertEq(next, depositStartDay + 17);

        // removing liquidity
        // 22th day, alice removes 2nd deposited liquidity, bob removes 2nd deposited liquidity, then alice removes 3nd deposited liquidited again
        vm.warp(block.timestamp + 4 days);
        vm.assertEq(liquidityMining.getUserTotalDeposit(alice), 3 ether);
        vm.prank(alice);
        liquidityMining.removeLiquidity(1);
        vm.assertEq(liquidityMining.getUserTotalDeposit(alice), 2.5 ether);
        // checking history
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 21);
        assertEq(amount, 2.5 ether);
        assertEq(prev, depositStartDay + 14);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 14);
        assertEq(next, depositStartDay + 21);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 21);
        assertEq(amount, 4.5 ether);
        assertEq(prev, depositStartDay + 17);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 17);
        assertEq(next, depositStartDay + 21);

        vm.assertEq(liquidityMining.getUserTotalDeposit(bob), 2 ether);
        vm.prank(bob);
        liquidityMining.removeLiquidity(1);
        vm.assertEq(liquidityMining.getUserTotalDeposit(bob), 1 ether);
        // checking history
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(bob, depositStartDay + 21);
        assertEq(amount, 1 ether);
        assertEq(prev, depositStartDay + 17);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getUserDailyCheckpoint(bob, depositStartDay + 17);
        assertEq(next, depositStartDay + 21);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 21);
        assertEq(amount, 3.5 ether);
        assertEq(prev, depositStartDay + 17);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 17);
        assertEq(next, depositStartDay + 21);

        vm.assertEq(liquidityMining.getUserTotalDeposit(alice), 2.5 ether);
        vm.prank(alice);
        liquidityMining.removeLiquidity(2);
        vm.assertEq(liquidityMining.getUserTotalDeposit(alice), 2 ether);
        // checking history
        (amount, prev, next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 21);
        assertEq(amount, 2 ether);
        assertEq(prev, depositStartDay + 14);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getUserDailyCheckpoint(alice, depositStartDay + 14);
        assertEq(next, depositStartDay + 21);
        (amount, prev, next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 21);
        assertEq(amount, 3 ether);
        assertEq(prev, depositStartDay + 17);
        assertEq(next, 0);
        ( , , next) = liquidityMining.getTotalDailyCheckpoint(depositStartDay + 17);
        assertEq(next, depositStartDay + 21);
    }
}
