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
        address user;
        uint256 amount;
        uint256 depositOn;
    }

    // address of sale token
    IERC20 public token;
    // address of reward token
    IERC20 public rewardToken;
    // address of claiming contract
    address public claiming;

    // deposit start time
    uint256 public depositStart;
    // minimum ETH amount to deposit
    uint256 public ALLOWED_MINIMUM_DEPOSIT;
    // total deposit ETH
    uint256 private totalDeposits;
    // user's deposit ETH
    UserDeposit[] private userDeposits;
    // user's index in UserDeposit array
    mapping(address => uint256) private userDepositIndex;

    // UniswapV2 factory
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Router02 public uniswapV2Router;

    /* ========== EVENTS ========== */
    // Event emitted when a presale buyer deposits ETH
    event Deposited(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);
    // Event emitted when an owner updates the time to start deposit
    event DepositStartTimeUpdated(address indexed user, uint256 depositStartTime);
    // Event emitted when an owner deposits sale token
    event SaleTokenDeposited(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a owner withdraws token
    event SaleTokenWithdrawed(address indexed user, uint256 amount, uint256 time);
    // Event emitted when liquidity is added and LP token is minted
    event LiquidityAdded(address indexed user, uint256 liqudity, uint256 time);
    // Event emitted when allowed minimum deposit amount is updated
    event AllowedMinimumDepositUpdated(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);

    modifier onlyPresaleBuyer() {
        require(claiming != address(0), "The address of claiming contract cannot be zero");
        require(IClaiming(claiming).getClaimInfoIndex(msg.sender) > 0, "Caller should be presale buyer");
        _;
    }

    constructor(address _token, address _rewardToken) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Sale token address cannot be zero");
        require(_rewardToken != address(0), "Reward token address cannot be zero");

        token = IERC20(_token);
        rewardToken = IERC20(_rewardToken);

        // set uniswap factory and router02
        uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        // push empty element to the UserDeposit array for convenience
        userDeposits.push(UserDeposit({
            user: address(0),
            amount: 0,
            depositOn: 0
        }));
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

    function depositETH() external payable onlyPresaleBuyer nonReentrant {
        // verify if deposit is allowed
        require(depositStart != 0 && block.timestamp >= depositStart, "Deposit is not allowed for now");

        if (ALLOWED_MINIMUM_DEPOSIT > 0) {
            require(msg.value >= ALLOWED_MINIMUM_DEPOSIT, "Insufficient deposit amount for minimum allowed");
        }

        uint256 previousAmount;

        uint256 index = userDepositIndex[msg.sender];
        if (index != 0) {
            // update previous deposit data
            UserDeposit storage userDeposit = userDeposits[index];
            previousAmount = userDeposit.amount;
            // increase deposit amount
            userDeposit.amount += msg.value;
        } else {
            // save index of newly pushed deposit info
            userDepositIndex[msg.sender] = userDeposits.length;
            // push new user's deposit info
            userDeposits.push(UserDeposit({
                user: msg.sender,
                amount: msg.value,
                depositOn: block.timestamp
            }));
        }

        // increase total deposit amount
        totalDeposits += msg.value;

        emit Deposited(msg.sender, previousAmount, previousAmount + msg.value, block.timestamp);
    }

    /**
     * @notice Deposit sale token that will be used to add liquidity
     *
     * @dev only owner can call this function
     *
     * @param amount the amount to be deposited
     */
    function depositToken(uint256 amount) external onlyOwner {
        // verify input argument
        require(amount > 0, "Cannot deposit zero amount");

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit SaleTokenDeposited(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Withdraw deposited sale token back
     *
     * @dev only owner can call this function
     *
     * @param amount the amount to be withdrawn
     */
    function withdrawToken(uint256 amount) external onlyOwner {
        // verify input argument
        require(amount > 0, "Cannot withdraw zero amount");

        token.safeTransfer(owner(), amount);

        emit SaleTokenWithdrawed(owner(), amount, block.timestamp);
    }

    /**
     * @notice Add liqudity of ETH/Token to UniV2
     *
     * @param amount the amount of sale token to be provided
     */
    function addLiquidity(uint256 amount) external onlyOwner {
        // verify sufficient balance of sale token to add liqudity
        require(amount <= getTokenBalance(), "Insufficient sale token to mint LP");
        // verify sufficient ETH balance to add liquidity
        require(totalDeposits != 0, "Insufficient ETH balance to mint LP");

        // Approve router to mint LP
        token.approve(address(uniswapV2Router), amount);

        try uniswapV2Router.addLiquidityETH{value: totalDeposits} ( // Amount of AVAX to send for LP on main dex
            address(token),
            amount,
            100, // Infinite slippage basically since it's in wei
            100, // Infinite slippage basically since it's in wei
            address(this), // Transfer LP token to this contract
            block.timestamp
        )  returns (uint256 , uint256 , uint256 liquidity) {
            totalDeposits = 0;

            emit LiquidityAdded(msg.sender, liquidity, block.timestamp);
        } catch {
            revert(string("Adding liqudity was failed"));
        }
    }

    /*****************************************************
                            Getter
    *****************************************************/

    /**
     * @notice Get the total amount of sale token of this contract
     */
    function getTokenBalance() public view returns(uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Get the reward token amount for deposited ETH
     *
     * @param user address of user to get the reward
     *
     * TODO should consider mining is performed
     */
    function getRewardTokenAmount(address user) public view returns(uint256) {
        uint256 index = userDepositIndex[user];

        // If user never deposit ETH, return 0
        if (index == 0) return 0;

        address pair = getPair();
        // If pair pool wasn't created, return 0
        if (pair == 0) return 0;

        uint256 liquidity = IUniswapV2Pair(pair).balanceOf(address(this));
        // If liquidity is 0, return 0
        if (liquidity == 0) return 0;
        
        UserDeposit storage userDeposit = userDeposits[index];
        return 0;
    }

    /**
     * @notice Get the address of pair pool of sale token and WETH
     */
    function getPair() public view returns(address pair) {
        pair = uniswapV2Factory.getPair(token, uniswapV2Router.WETH());
    }
}

