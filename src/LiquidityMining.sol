// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IClaiming.sol";

contract LiquidityMining is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserDeposit {
        address user;
        uint256 amount;
    }

    // address of sale token
    IERC20 public token;
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
    IUniswapV2Factory public UNI_FACTORY;
    IUniswapV2Router02 public UNI_ROUTER;

    /* ========== EVENTS ========== */
    // Event emitted when a presale buyer deposits ETH
    event Deposited(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);
    // Event emitted when an owner updates the time to start deposit
    event DepositStartTimeUpdated(address indexed user, uint256 depositStartTime);
    // Event emitted when an owner deposits sale token
    event SaleTokenDeposited(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a owner withdraws token
    event SaleTokenWithdrawed(address indexed user, uint256 amount, uint256 time);

    modifier onlyPresaleBuyer() {
        require(claiming != address(0), "The address of claiming contract cannot be zero");
        require(IClaiming(claiming).getClaimInfoIndex(msg.sender) > 0, "Caller should be presale buyer");
        _;
    }

    constructor(address _token) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Sale token address cannot be zero");

        // set uniswap factory and router02
        UNI_FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        UNI_ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        // push empty element to the UserDeposit array for convenience
        userDeposits.push(UserDeposit({
            user: address(0),
            amount: 0
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
        if (index > 0) {
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
                amount: msg.value
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
    function withdraw(uint256 amount) external onlyOwner {
        // verify input argument
        require(amount > 0, "Cannot withdraw zero amount");

        token.safeTransfer(owner(), amount);

        emit SaleTokenWithdrawed(owner(), amount, block.timestamp);
    }

    /*****************************************************
                            Setter
    *****************************************************/

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
}

