// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
    // address of reward token
    IERC20 public rewardToken;
    // address of claiming contract
    address public claiming;

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
    uint256 private totalDeposits;
    // user's deposit ETH
    mapping(address => UserDeposit[]) public userDeposits;
    // total deposited amount of each user
    mapping(address => uint256) private userTotalDeposits;

    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;

    /* ========== EVENTS ========== */
    // Event emitted when a presale buyer deposits ETH
    event Deposited(address indexed user, uint256 amount, uint256 time);
    // Event emitted when an owner updates the time to start deposit
    event DepositStartTimeUpdated(address indexed user, uint256 depositStartTime);
    // Event emitted when allowed minimum deposit amount is updated
    event AllowedMinimumDepositUpdated(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);
    // EVent emitted when liquidity removed by the depositor
    event liquidityRemoved(address indexed user, uint256 ownLiquidity, uint256 amountToken, uint256 amountETH, uint256 time);
    // EVent emitted when reward token is transferred
    event RewardTransferred(address indexed user, uint256 amount, uint256 time);

    constructor(address _token, address _rewardToken) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Sale token address cannot be zero");
        require(_rewardToken != address(0), "Reward token address cannot be zero");

        token = IERC20(_token);
        rewardToken = IERC20(_rewardToken);

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
     * @notice Set the reward token address
     * 
     * @param _rewardToken The address of reward token 
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        // verify input argument
        require(_rewardToken != address(0), "Token address cannot be zero.");

        rewardToken = IERC20(_rewardToken);
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
        require(_claiming != address(0), "Reward token address cannot be zero address");

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

    /******************************************************
                           External
    ******************************************************/

    function depositETH() external payable nonReentrant {
        // only presale buyer can deposit ETH
        require(claiming != address(0), "The address of claiming contract cannot be zero");
        require(IClaiming(claiming).getClaimInfoIndex(msg.sender) > 0, "Caller should be presale buyer");

        // verify if deposit is allowed
        require(depositStart != 0 && block.timestamp >= depositStart, "Deposit is not allowed for now");

        if (ALLOWED_MINIMUM_DEPOSIT > 0) {
            require(msg.value >= ALLOWED_MINIMUM_DEPOSIT, "Insufficient deposit amount for minimum allowed");
        }

        userDeposits[msg.sender].push(UserDeposit({
            amount: msg.value,
            depositOn: block.timestamp,
            removed: false
        }));

        userTotalDeposits[msg.sender] += msg.value;

        // increase total deposit amount
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value, block.timestamp);
    }

    function removeLiquidity(uint256 index) external nonReentrant {
        // verify input argument
        require(index < userDeposits[msg.sender].length, "Invalid index value");
        
        UserDeposit storage userDeposit = userDeposits[msg.sender][index];
        require(!userDeposit.removed, "This liquidity was already removed");
        
        // update the removed flag as true
        userDeposit.removed = true;
        uint256 liquidity = getLPBalance();

        // valid if liquidity exists
        require(liquidity != 0, "There is no liquidity in the contract");
        
        uint256 ownLiquidity = liquidity * userDeposit.amount / totalDeposits;
        
        (uint256 amountToken, uint256 amountETH) = uniswapV2Router.removeLiquidityETH(
            address(token),
            ownLiquidity,
            100,
            100,
            msg.sender,
            block.timestamp
        );

        emit liquidityRemoved(msg.sender, ownLiquidity, amountToken, amountETH, block.timestamp);

        // transfer reward token
        uint256 rewardAmount = getRewardTokenAmount(msg.sender, index);
        rewardToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardTransferred(msg.sender, rewardAmount, block.timestamp);
    }

    /*****************************************************
                            Getter
    *****************************************************/

    function getLPBalance() public view returns (uint256 liquidity) {
        address pair = getPair();
        // If pair pool wasn't created, return 0
        if (pair == address(0)) return 0;

        liquidity = IUniswapV2Pair(pair).balanceOf(address(this));
    }
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
     * @notice Get the address of pair pool of sale token and WETH
     */
    function getPair() public view returns(address pair) {
        pair = uniswapV2Factory.getPair(address(token), WETH);
    }
}

