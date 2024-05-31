// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IAggregatorV3Interface.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IClaiming.sol";

contract LiquidityMining is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserDeposit {
        uint256 amount;
        uint256 depositOn;
        bool removed;
    }

    // address of sale token
    IERC20 public token;
    // address of claiming contract
    address public claiming;

    // status for liquidity is added
    uint256 public listedTime;
    // liquidity amount to be listed
    uint256 public liquidity;

    // deposit start time, i.e the time presale is over
    uint256 public depositStart;
    
    uint256 public REWARD_RATE_1M = 10_000;
    uint256 public REWARD_RATE_2M = 5_000;
    uint256 public REWARD_RATE_3M = 2_500;
    uint256 public REWARD_RATE_4M = 1_500;
    uint256 public REWARD_RATE_5M = 1_000;
    uint256 public DENOMINATOR = 10_000;
    // minimum ETH amount to deposit
    uint256 public ALLOWED_MINIMUM_DEPOSIT;
    // minimum period to lock ETH;
    uint256 public MININUM_PERIOD_LOCK_ETH;
    // WETH token address
    address public WETH;
    // total deposit ETH
    uint256 public totalDeposits;
    // user's deposit ETH
    mapping(address => UserDeposit[]) public userDeposits;
    // total deposited amount of each user
    mapping(address => uint256) public userTotalDeposits;

    // states for reward
    mapping(address => uint256 => uint256) public userDailyHistory; // user => day => amount
    mapping(address => uint256) public userLastUpdateDay; // user => day
    mapping(uint256 => uint256) public dailyTotalHistory; // day => amount
    uint256 public lastUpdateDay;

    IUniswapV2Pair public pair;
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;

    AggregatorV3Interface internal chainlinkETHUSDContract;

    /* ========== EVENTS ========== */
    // Event emitted when a presale buyer deposits ETH
    event Deposited(address indexed user, uint256 amount, uint256 time);
    // Event emitted when an owner updates the time to start deposit
    event DepositStartTimeUpdated(address indexed user, uint256 depositStartTime);
    // Event emitted when allowed minimum deposit amount is updated
    event AllowedMinimumDepositUpdated(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);
    // Event emitted when liquidity added by the owner
    event LiquidityAdded(address indexed user, uint256 liquidity, uint256 time);
    // Event emitted when liquidity removed by the depositor
    event LiquidityRemoved(address indexed user, uint256 ownLiquidity, uint256 amountToken, uint256 amountETH, uint256 time);
    // Event emitted when reward token is transferred
    event RewardTransferred(address indexed user, uint256 amount, uint256 time);

    modifier onlyWhenNotListed() {
        require(listedTime == 0, "Liquidity was already listed");
        _;
    }

    constructor(address _token, address _chainlinkETHUSDAddress) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Sale token address cannot be zero");

        token = IERC20(_token);

        chainlinkETHUSDContract = AggregatorV3Interface(_chainlinkETHUSDAddress);

        // set uniswap factory and router02
        uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        // set the WETH token address
        WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        MININUM_PERIOD_LOCK_ETH = 30 days;
    }

    /******************************************************
                            Setter
    ******************************************************/

    /**
     * @notice Set the sale token address
     * 
     * @param _token The address of sale token 
     */
    function setToken(address _token) external onlyOwner {
        // verify input argument
        require(_token != address(0), "Token address cannot be zero.");

        token = IERC20(_token);
    }

    /**
     * @notice Set the WETH token address
     * 
     * @param _WETH The address of WETH token 
     */
    function setWETH(address _WETH) external onlyOwner {
        // verify input argument
        require(_WETH != address(0), "Token address cannot be zero.");

        WETH = _WETH;
    }

    /**
     * @notice Set the time to start claiming
     *
     * @param _depositStart The time to start claiming
     */
    function setDepositStart(uint256 _depositStart) external onlyOwner {
        // verify input argument
        require(_depositStart > block.timestamp, "Invalid time for start deposit.");

        depositStart = _depositStart;

        emit DepositStartTimeUpdated(msg.sender, _depositStart);
    }

    /**
     * @notice Set the address of claiming contract
     * 
     * @dev Only owner can call this function; should check non-zero address
     * 
     * @param _claiming address of the claiming contract
     */
    function setClaimingContract(address _claiming) external onlyOwner {
        // verify input argument
        require(_claiming != address(0), "Contract address cannot be zero address");

        claiming = _claiming;
    }

    /**
     * @notice Set the minimum allowed to deposit ETH
     *
     * @dev amount can be zero value
     *
     * @param amount allowed minimum amount to deposit ETH
     */
    function setAllowedMinimumDeposit(uint256 amount) external onlyOwner {
        uint256 previousAmount = ALLOWED_MINIMUM_DEPOSIT;
        ALLOWED_MINIMUM_DEPOSIT = amount;

        emit AllowedMinimumDepositUpdated(msg.sender, previousAmount, amount, block.timestamp);
    }

    /**
     * @notice Set the uniswap v2 pair contract
     *
     * @param _pair the address of the pair pool
     */
    function setPair(address _pair) external onlyOwner {
        // verify input argument
        require(_pair != address(0), "Pair address cannot be zero");

        pair = IUniswapV2Pair(_pair);
    }

    /******************************************************
                           External
    ******************************************************/

    /**
     * @notice deposit ETH for liquidity mining
     */
    function depositETH() external payable nonReentrant onlyWhenNotListed {
        require(msg.value > 0, "Cannot deposit 0 ETH");
        // verify if deposit is allowed
        require(depositStart != 0 && block.timestamp >= depositStart, "Deposit is not allowed for now");

        if (ALLOWED_MINIMUM_DEPOSIT > 0) {
            require(msg.value >= ALLOWED_MINIMUM_DEPOSIT, "Insufficient deposit amount for minimum allowed");
        }

        (
            bool depositable,
            uint256 claimableAmount,
            uint256 ethValue
        ) = _checkClaimableAmountForDepositETH(msg.sender, msg.value);
        
        // only presale buyer can deposit ETH
        require(depositable, "You don't have sufficient claimable token amount to deposit ETH");

        // decrease the user's claimable token amount by deposited ETH market value
        IClaiming(claiming).setClaim(msg.sender, claimableAmount - ethValue);

        userDeposits[msg.sender].push(UserDeposit({
            amount: msg.value,
            depositOn: block.timestamp,
            removed: false
        }));

        userTotalDeposits[msg.sender] += msg.value;

        // increase total deposit amount
        totalDeposits += msg.value;

        _updateHistoryForReward(msg.sender, msg.value);

        emit Deposited(msg.sender, msg.value, block.timestamp);
    }

    function _updateHistoryForReward(address user, uint256 amount) private {
        // get the today number
        uint256 today = block.timestamp / 86400;

        if (userDailyHistory[user][today] == 0) {
            // if it is the first updating for today, update with last update day's amount
            uint256 lastDay = userLastUpdateDay[user];
            userDailyHistory[user][today] = userDailyHistory[user][lastDay];
        }

        userDailyHistory[user][today] += amount;
        userLastUpdateDay[user] = today;
    }

    /**
     * @notice Add liquidity of ETH/Token to UniV2
     *
     * @param _pair the address of pair pool on Uni v2
     */
    function listLiquidity(address _pair) external onlyOwner onlyWhenNotListed {
        require(address(token) != address(0), "Sale token address cannot be zero");

        // verify passed pair address with sale token and WETH 
        // require(uniswapV2Factory.getPair(address(token), WETH) == _pair, "The pair address is invalid");
        
        // verify sufficient ETH balance to add liquidity
        require(totalDeposits != 0, "Insufficient ETH balance to mint LP");

        pair = IUniswapV2Pair(_pair);

        listedTime = block.timestamp;

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amount;
        if (address(token) < WETH) {
            amount = uniswapV2Router.quote(totalDeposits, reserve1, reserve0);
        } else {
            amount = uniswapV2Router.quote(totalDeposits, reserve0, reserve1);
        }

        // get the sale token from the claiming contract for adding liquidity
        IClaiming(claiming).transferTokenToLiquidityMining(amount);

        // Approve router to mint LP
        token.approve(address(uniswapV2Router), amount);

        try uniswapV2Router.addLiquidityETH{value: totalDeposits} ( // Amount of ETH to send for LP on univ2
            address(token),
            2 * amount, // to calc as WETH desired quote
            100, // Infinite slippage basically since it's in wei
            totalDeposits, // should add liquidity this amount exactly
            address(this), // Transfer LP token to this contract
            block.timestamp
        ) returns (uint256 , uint256 , uint256 liquidityAmount) {
            liquidity = liquidityAmount;

            emit LiquidityAdded(msg.sender, liquidityAmount, block.timestamp);
        } catch {
            revert(string("Adding liquidity was failed"));
        }
    }

    /**
     * @notice cancel liquidity mining to receive back funds
     *
     * @dev able to only after 7 days later from listing
     *
     * @param index index of the deposit array to get reward
     */
    function removeLiquidity(uint256 index) external nonReentrant {
        // verify 1 week after listed
        require(listedTime != 0 && block.timestamp >= listedTime + 7 days, "Cannot remove liquidity until 7 days after listing");
        // verify input argument
        require(index < userDeposits[msg.sender].length, "Invalid index value");
        
        UserDeposit storage userDeposit = userDeposits[msg.sender][index];
        require(!userDeposit.removed, "This liquidity was already removed");
        
        // update the removed flag as true
        userDeposit.removed = true;

        // valid if liquidity exists
        require(liquidity != 0, "There is no liquidity in the contract");
        
        uint256 ownLiquidity = liquidity * userDeposit.amount / totalDeposits;

        pair.approve(address(uniswapV2Router), ownLiquidity);
        
        // remove liquidity and transfer tokens to caller
        (uint256 amountToken, uint256 amountETH) = uniswapV2Router.removeLiquidityETH(
            address(token),
            ownLiquidity,
            100,
            100,
            msg.sender,
            block.timestamp
        );

        emit LiquidityRemoved(msg.sender, ownLiquidity, amountToken, amountETH, block.timestamp);

        // transfer reward token
        // uint256 rewardAmount = getRewardTokenAmount(msg.sender, index);
        // token.safeTransfer(msg.sender, rewardAmount);

        // emit RewardTransferred(msg.sender, rewardAmount, block.timestamp);
    }

    /*****************************************************
                            Getter
    *****************************************************/

    /**
     * @notice Get the reward token amount for deposited ETH
     *
     * @param user address of user to get the reward
     * @param index index of the deposit array to get reward
     *
     * TODO should consider mining is performed
     */
    function getRewardTokenAmount(address user, uint256 index) public view returns(uint256 rewardAmount) {
        // verify input argument
        require(user != address(0), "Invalid user address");
        require(index < userDeposits[msg.sender].length, "Invalid index value");
        
        UserDeposit storage userDeposit = userDeposits[user][index];

        uint256 depositAmount = userDeposit.amount;

        uint256 period = block.timestamp - userDeposit.depositOn;
        if (period <= 30 days) {
            rewardAmount = depositAmount * REWARD_RATE_1M / DENOMINATOR;
        } else if (period <= 60 days) {
            rewardAmount = depositAmount * REWARD_RATE_2M / DENOMINATOR;
        } else if (period <= 90 days) {
            rewardAmount = depositAmount * REWARD_RATE_3M / DENOMINATOR;
        } else if (period <= 120 days) {
            rewardAmount = depositAmount * REWARD_RATE_4M / DENOMINATOR;
        } else {
            rewardAmount = depositAmount * REWARD_RATE_5M / DENOMINATOR;
        }
    }

    /**
     * @notice get user's deposit info at particular index
     *
     * @param user address of the user to get the info
     * @param index index of the deposit array of user
     */
    function getUserDepositInfo(
        address user,
        uint256 index
    ) public view returns (
        uint256,
        uint256,
        bool
    ) {
        UserDeposit storage userDeposit = userDeposits[user][index];

        return (
            userDeposit.amount,
            userDeposit.depositOn,
            userDeposit.removed
        );
    }

    /**
     * @notice get user's total deposited ETH amount
     */
    function getUserTotalDeposit(address user) public view returns(uint256) {
        return userTotalDeposits[user];
    }

    /**
     * @notice get the lates ETH/USD price from chainlink price feed
     */
    function fetchETHUSDPrice() public view returns (uint256 price, uint256 decimals) {
        (, int256 priceInt, , , ) = chainlinkETHUSDContract.latestRoundData();
        decimals = chainlinkETHUSDContract.decimals();
        price = uint256(priceInt);
        return (price, decimals);
    }

    function _checkClaimableAmountForDepositETH(
        address user,
        uint256 ethAmount
    ) private view returns (
        bool depositable,
        uint256 claimableAmount,
        uint256 ethValue
    ) {
        // verify claiming contract address
        require(claiming != address(0), "The address of claiming contract cannot be zero");
        
        // get the latest ETH price and decimals
        (uint256 price, uint256 decimals) = fetchETHUSDPrice();

        // calculate deposited ETH market value
        // @note (didn't divide with 10 ** 18, because the sale token's decimals is also 18)
        ethValue = ethAmount * price / (10 ** decimals);

        // get current claimable token amount for user
        claimableAmount = IClaiming(claiming).getClaimableAmount(user);
        
        depositable = claimableAmount >= ethValue;
    }
}

