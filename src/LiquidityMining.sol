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
        uint256 liquidity;
        bool removed;
    }

    struct Checkpoint {
        uint256 amount;
        uint256 prev;
        uint256 next;
    }

    // address of sale token
    IERC20 public token;
    // address of claiming contract
    address public claiming;

    // status for liquidity is added
    uint256 public listedTime;
    // liquidity amount to be listed
    uint256 public listedLiquidity;

    // deposit start time, i.e the time presale is over
    uint256 public depositStart;
    
    // minimum ETH amount to deposit
    uint256 public ALLOWED_MINIMUM_DEPOSIT;
    // WETH token address
    address public WETH;
    // total deposit ETH until list the liquidity
    uint256 public totalDeposits;
    // user's deposit ETH
    mapping(address => UserDeposit[]) public userDeposits;
    // total deposited amount of each user
    mapping(address => uint256) public userTotalDeposits;

    // states for reward
    uint256 public startDay;
    uint256 public rewardPeriod;
    uint256 public totalReward;
    mapping(address => mapping(uint256 => Checkpoint)) public userDailyHistory; // user => day => amount
    mapping(address => uint256) public userLastUpdateDay; // user => day (last day that daily history was updated)
    mapping(address => uint256) public lastRewardClaimDay; // user => day (last day that claimed reward)
    mapping(address => uint256) public lastCheckpointDay; // user => day (last day that was considered in reward calculation for user deposit)
    mapping(address => uint256) public lastTotalCheckpointDay; // user => day (last day that was considered in reward calculation for total deposit)
    mapping(uint256 => Checkpoint) public dailyTotalHistory; // day => amount
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
    // Event emitted when claiming contract address was updated by the owner
    event ClaimingContractAddressUpdated(address indexed user, address claiming, uint256 time);
    // Event emitted when liquidity added by the owner
    event LiquidityAdded(address indexed user, uint256 liquidity, uint256 time);
    // Event emitted when liquidity removed by the depositor
    event LiquidityRemoved(address indexed user, uint256 ownLiquidity, uint256 amountToken, uint256 amountETH, uint256 time);
    // Event emitted when reward token is transferred
    event RewardTransferred(address indexed user, uint256 amount, uint256 time);
    // Event emitted when reward token is deposited by the owner
    event TokenDepositedForReward(address indexed user, uint256 amount, uint256 time);
    // Event emitted when the owner updates the reward program states
    event RewardProgramPlanUpdated(address indexed user, uint256 startDay, uint256 period, uint256 totalReward, uint256 time);

    modifier onlyWhenNotListed() {
        require(listedTime == 0, "Liquidity was already listed");
        _;
    }

    modifier onlyWhenListed() {
        require(listedTime != 0, "Liquidity wasn't listed yet");
        _;
    }

    constructor(
        address _token,
        address _chainlinkETHUSDAddress,
        address _uniswapV2Factory, // 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
        address _uniswapV2Router // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    ) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Sale token address cannot be zero");

        token = IERC20(_token);

        chainlinkETHUSDContract = AggregatorV3Interface(_chainlinkETHUSDAddress);

        // set uniswap factory and router02
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Factory);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);

        // set the WETH token address
        WETH = uniswapV2Router.WETH();
    }

    /******************************************************
                            Setter
    ******************************************************/

    /**
     * @notice Set the time to start claiming
     *
     * @param _depositStart The time to start claiming
     */
    function setDepositStart(uint256 _depositStart) external onlyOwner {
        // verify input argument
        require(_depositStart >= block.timestamp, "Invalid time for start deposit.");

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

        emit ClaimingContractAddressUpdated(msg.sender, claiming, block.timestamp);
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
     * @notice Set the states for reward program
     *
     * @param _period reward program period in days
     * @param _start reward program start time in timestamp
     * @param _total total reward token amount
     */
    // @audit need test
    function setRewardStates(uint256 _start, uint256 _period, uint256 _total) external onlyOwner {
        // verify setting of deposit start date
        require(depositStart != 0, "Deposit start time should be set");

        // verify input argument
        require(_start != 0, "Invalid reward start time");
        require(_start >= depositStart, "Cannot be before deposit start time");
        require(_period != 0, "Invalid reward period");
        require(_total != 0, "Invalid reward token amount");

        // set the start day at the 00h:00min of the start day
        startDay = _start / 1 days;

        uint256 day = depositStart / 1 days;
        Checkpoint storage startDayCp = dailyTotalHistory[startDay];
        while (day <= startDay) {
            Checkpoint memory dayCp = dailyTotalHistory[day];
            if (dailyTotalHistory[day].amount != 0) {
                startDayCp.amount = dayCp.amount;
                startDayCp.prev = dayCp.prev;
                startDayCp.next = dayCp.next;
            }

            ++day;
        }

        rewardPeriod = _period;
        totalReward = _total;

        emit RewardProgramPlanUpdated(msg.sender, startDay, rewardPeriod, totalReward, block.timestamp);
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
            liquidity: 0,
            removed: false
        }));

        userTotalDeposits[msg.sender] += msg.value;

        // increase total deposit amount
        totalDeposits += msg.value;

        _updateHistoryForReward(msg.sender, msg.value, false);

        emit Deposited(msg.sender, msg.value, block.timestamp);
    }

    // @audit need test
    function _updateHistoryForReward(address user, uint256 amount, bool isRemove) private {
        // get the today number
        uint256 today = block.timestamp / 1 days;

        Checkpoint storage todayCp = userDailyHistory[user][today];
        if (today != userLastUpdateDay[user]) {
            // if it is the first updating for today, update with last update day's amount
            uint256 userLastDay = userLastUpdateDay[user];
            Checkpoint storage lastCp = userDailyHistory[user][userLastDay];
            todayCp.amount = lastCp.amount;
            // update today's previous checkpoint day
            todayCp.prev = userLastDay;
            // update last checkpoint day's next checkpoint day
            lastCp.next = today;
        }

        Checkpoint storage todayTotalCp = dailyTotalHistory[today];
        if (today != lastUpdateDay) {
            Checkpoint storage lastTotalCp = dailyTotalHistory[lastUpdateDay];
            todayTotalCp.amount = lastTotalCp.amount;
            todayTotalCp.prev = lastUpdateDay;
            lastTotalCp.next = today;
        }

        if (isRemove) {
            todayCp.amount -= amount;
            todayTotalCp.amount -= amount;
        } else {
            todayCp.amount += amount;
            todayTotalCp.amount += amount;
        }
        userLastUpdateDay[user] = today;
        lastUpdateDay = today;
        // udpate the first checkpoint for reward
        if (today <= startDay) {
            Checkpoint storage startDayCp = userDailyHistory[user][startDay];
            startDayCp.amount = todayCp.amount;
            startDayCp.prev = todayCp.prev;
            startDayCp.next = 0;

            Checkpoint storage startDayTotalCp = dailyTotalHistory[startDay];
            startDayTotalCp.amount = todayTotalCp.amount;
            startDayTotalCp.prev = todayTotalCp.prev;
            startDayTotalCp.next = todayTotalCp.next;
        }
    }

    /**
     * @notice List liquidity of deposited ETH and some Token to UniV2
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
        require(pair.token0() == address(token) || pair.token1() == address(token), "Invalid pair address");

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
        bool success = token.approve(address(uniswapV2Router), amount);
        require(success, "Approve failed");

        try uniswapV2Router.addLiquidityETH{value: totalDeposits} ( // Amount of ETH to send for LP on univ2
            address(token),
            2 * amount, // to calc as WETH desired quote
            100, // Infinite slippage basically since it's in wei
            totalDeposits, // should add liquidity this amount exactly
            address(this), // Transfer LP token to this contract
            block.timestamp
        ) returns (uint256 , uint256 , uint256 liquidity) {
            listedLiquidity = liquidity;

            emit LiquidityAdded(msg.sender, listedLiquidity, block.timestamp);
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
    // @audit need test
    function removeLiquidity(uint256 index) external nonReentrant onlyWhenListed returns(
        uint256 amountToken,
        uint256 amountETH
    ){
        // verify 1 week after listed
        require(block.timestamp >= listedTime + 7 days, "Cannot remove liquidity until 7 days after listing");
        // verify input argument
        require(index < userDeposits[msg.sender].length, "Invalid index value");
        
        UserDeposit storage userDeposit = userDeposits[msg.sender][index];
        require(!userDeposit.removed, "This liquidity was already removed");
        
        // update the removed flag as true
        userDeposit.removed = true;

        userTotalDeposits[msg.sender] -= userDeposit.amount;

        uint256 ownLiquidity;
        if (userDeposit.liquidity != 0) {
            // if liquidity after listing
            ownLiquidity = userDeposit.liquidity;
        } else {
            // if liquidity before listing
            // valid if liquidity exists
            require(listedLiquidity != 0, "There is no liquidity in the contract");
            
            ownLiquidity = listedLiquidity * userDeposit.amount / totalDeposits;
        }

        bool success = pair.approve(address(uniswapV2Router), ownLiquidity);
        require(success, "Approve failed");
        
        // remove liquidity and transfer tokens to caller
        (amountToken, amountETH) = uniswapV2Router.removeLiquidityETH(
            address(token),
            ownLiquidity,
            100,
            100,
            msg.sender,
            block.timestamp
        );

        _updateHistoryForReward(msg.sender, userDeposit.amount, true);

        emit LiquidityRemoved(msg.sender, ownLiquidity, amountToken, amountETH, block.timestamp);
    }

    /**
     * @notice add liquidity after presale buyers' liquidity was listed
     *
     * @param amount sale token amount to add liquidity
     */
    // @audit need test
    function addLiquidity(uint256 amount)external payable nonReentrant onlyWhenListed returns(
        uint256 aToken,
        uint256 aETH,
        uint256 aLiquidity
    ) {
        require(msg.value != 0, "Invalid ETH deposit");
        require(amount != 0 , "Invalid token deposit");

        // transfer token from user to mining contract here
        token.safeTransferFrom(msg.sender, address(this), amount);
        // approve router to transfer token from mining to pair
        bool success = token.approve(address(uniswapV2Router), amount);
        require(success, "Approve failed");

        // add liquidity by depositing both of token and ETH
        try uniswapV2Router.addLiquidityETH{value: msg.value} (
            address(token),
            amount, // to calc as WETH desired quote
            100, // Infinite slippage basically since it's in wei
            100, // Infinite slippage basically since it's in wei
            address(this), // Transfer LP token to this contract
            block.timestamp
        ) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
            if (amount > amountToken) {
                // refund left token to the user back
                token.safeTransfer(msg.sender, amount - amountToken);
            }

            if (msg.value > amountETH) { // no need, but for security
                // refund left ETH to the user back
                ( success, ) = address(msg.sender).call{
                    value: msg.value - amountETH,
                    gas: 35000 // limit gas fee to prevent hook operation
                }("");
                require(success, "Failed to refund Ether");
            }

            userDeposits[msg.sender].push(UserDeposit({
                amount: amountETH,
                depositOn: block.timestamp,
                liquidity: liquidity,
                removed: false
            }));

            userTotalDeposits[msg.sender] += amountETH;

            _updateHistoryForReward(msg.sender, amountETH, false);

            aToken = amountToken;
            aETH = amountETH;
            aLiquidity = liquidity;

            emit LiquidityAdded(msg.sender, liquidity, block.timestamp);
        } catch {
            revert(string("Adding liquidity was failed"));
        }
    }

    /**
     * @notice claim reward based on the daily reward program
     */
    // @audit need test
    function claimReward() external {
        // verify deposit and reward start time
        require(depositStart > 0, "Invalid deposit start time");
        require(startDay > 0, "Invalid reward start time");
        require(block.timestamp / 1 days > startDay, "Invalid date to claim reward");

        // if it is first claiming, update checkpoint for reward start day
        updateCheckpointStartDay(msg.sender);

        (
            uint256 rewardAmount,
            uint256 lastCpDay, 
            uint256 lastTotalCpDay
        ) = getRewardTokenAmount(msg.sender);

        if (rewardAmount > 0)
            token.safeTransfer(msg.sender, rewardAmount);

        // update last claim day as today
        lastRewardClaimDay[msg.sender] = block.timestamp / 1 days;
        lastCheckpointDay[msg.sender] = lastCpDay;
        lastTotalCheckpointDay[msg.sender] = lastTotalCpDay;
    }

    /**
     * @notice update start day's checkpoint info for particular user
     */
    function updateCheckpointStartDay(address user) public {
        // if it is first claiming, update checkpoint for reward start day
        Checkpoint storage startDayCp = userDailyHistory[user][startDay];
        if (
            lastRewardClaimDay[user] == 0 &&
            startDayCp.amount == 0
        ) {
            uint256 day = 0;
            while (day <= startDay) {
                Checkpoint memory dayCp = userDailyHistory[user][day];
                startDayCp.amount = dayCp.amount;
                startDayCp.prev = dayCp.prev;
                startDayCp.next = dayCp.next;

                if (dayCp.next != 0) {
                    day = dayCp.next;
                } else {
                    break;
                }
            }
        }
    }

    /**
     * @notice deposit tokens for reward program of liquidity mining
     */
    function depositRewardTokens(uint256 amount) external onlyOwner {
        // verity input argument
        require(amount != 0, "Invalid token amount");

        // transfer token for reward from caller to this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit TokenDepositedForReward(msg.sender, amount, block.timestamp);
    }

    /*****************************************************
                            Getter
    *****************************************************/

    /**
     * @notice How many deposits a particular address has done
     *
     * @param user an address to query number of times deposited
     * @return number of times a particular address has deposited
     */
    function numDepoists(address user) public view returns(uint256) {
        return userDeposits[user].length;
    }

    /**
     * @notice Get the reward token amount based on the reward program
     *
     * @param user address of user to get the reward
     */
    function getRewardTokenAmount(address user) public view returns(
        uint256 rewardAmount,
        uint256 lastCpDay,
        uint256 lastTotalCpDay
    ) {
        // verify input argument
        require(user != address(0), "Invalid user address");
        if (startDay == 0) { // in the case that start day is not defined yet
            rewardAmount = 0;
            lastCpDay = 0;
            lastTotalCpDay = 0;
        } else {
            // get the daily rewardable amount
            uint256 dailyReward = totalReward / rewardPeriod;

            // get the today
            uint256 today = block.timestamp / 1 days;
            // get the reward end day (the next day of end day, indeed)
            uint256 rewardEndDay = startDay + rewardPeriod;
            // get the last day when user claimed reward
            uint256 lastClaimDay = lastRewardClaimDay[user] == 0 ? startDay : lastRewardClaimDay[user];

            lastCpDay = lastCheckpointDay[user];
            lastTotalCpDay = lastTotalCheckpointDay[user];
            uint256 endDay = today > rewardEndDay ?  rewardEndDay : today;
            for (uint256 day = lastClaimDay; day < endDay; ++day) {
                uint256 totalCpAmount;
                Checkpoint memory dayTotalCp = dailyTotalHistory[day];
                if (dayTotalCp.amount != 0 || dayTotalCp.prev != 0) {
                    totalCpAmount = dayTotalCp.amount;
                    lastTotalCpDay = day;
                } else {
                    totalCpAmount = dailyTotalHistory[lastTotalCpDay].amount;
                }

                if (totalCpAmount == 0) continue;

                Checkpoint memory dayCp = userDailyHistory[user][day];

                if (dayCp.amount != 0 || dayCp.prev != 0) {
                    rewardAmount += dailyReward * dayCp.amount / totalCpAmount;
                    lastCpDay = day;
                } else {
                    // continue if user deposit ETH is zero
                    Checkpoint memory userLastDayCp = userDailyHistory[user][lastCpDay];
                    if (userLastDayCp.amount == 0) continue;

                    rewardAmount += dailyReward * userLastDayCp.amount / totalCpAmount;
                }
            }
        }
    }

    /**
     * @notice Get the info of a particular deposits
     * 
     * @param user address of user to get the deposits info
     */
    function getUserDepositsArray(address user) public view returns(UserDeposit[] memory) {
        uint256 length = numDepoists(user);
        UserDeposit[] memory userDepositArray = new UserDeposit[](length);

        for (uint256 i = 0; i < length;) {
            userDepositArray[i] = userDeposits[user][i];

            unchecked {
                ++i;
            }
        }

        return userDepositArray;
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
     * @notice get user's daily checkpoint history
     */
    function getUserDailyCheckpoint(
        address user,
        uint256 day
    ) public view returns (
        uint256 amount,
        uint256 prev, 
        uint256 next
    ) {
        Checkpoint memory cp = userDailyHistory[user][day];
        amount = cp.amount;
        prev = cp.prev;
        next = cp.next;
    }

    /**
     * @notice get total daily checkpoint history
     */
    function getTotalDailyCheckpoint(uint256 day) public view returns(
        uint256 amount,
        uint256 prev,
        uint256 next
    ) {
        Checkpoint memory cp = dailyTotalHistory[day];
        amount = cp.amount;
        prev = cp.prev;
        next = cp.next;
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
        // @note (not divide with 10^18, because the sale token's decimals is also 18)
        ethValue = ethAmount * price / (10 ** decimals);

        // get current claimable token amount for user
        claimableAmount = IClaiming(claiming).getClaimableAmount(user);
        
        depositable = claimableAmount >= ethValue;
    }
}

