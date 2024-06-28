// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IStaking.sol";

contract Claiming is Ownable {
    using SafeERC20 for IERC20;

    // presale token
    IERC20 public token;
    // staking contract
    address public staking;
    // liquidity mining contract
    address public liquidityMining;
    // claiming start time
    uint256 public claimStart;

    // maximum array length for set batch claim info
    uint256 public MAX_BATCH_SET_CLAIM = 1_000;
    // vesting percent
    uint256 public VESTING_PER_MONTH = 2_500;
    uint256 public DENOMINATOR = 10_000;

    struct ClaimInfo {
        address user; // address of presale buyer
        uint256 amount; // initial claimable amount of user
        uint256 claimed; // claimed amount of user (by only claiming)
        uint256 remain; // remaining amount
    }

    // claim info array
    ClaimInfo[] private claimInfos;

    // claim info index
    mapping(address => uint256) private claimInfoIndex;

    /* ========== EVENTS ========== */
    // Event emitted when owner deposits token
    event Deposited(address indexed user, uint256 amount, uint256 time);
    // Event emitted when owner withdraws token
    event Withdrawed(address indexed user, uint256 amount, uint256 time);
    // Event emiited when owner updates the staking contract address
    event StakingContractAddressUpdated(address indexed user, address staking, uint256 time);
    // Event emiited when owner updates the liquidityMining contract address
    event LiquidityMiningContractAddressUpdated(address indexed user, address liquidityMining, uint256 time);
    // Event emitted when owner updates the time to start claiming
    event ClaimStartTimeUpdated(address indexed user, uint256 claimStartTime);
    // Event emitted when owner updates the time to start claiming
    event ClaimInfoUpdated(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);
    // Event emitted when a user claimed his token
    event Claimed(address indexed user, address indexed beneficiary, uint256 amount, uint256 time);
    // Event emitted whan a user stake directly without 
    event Staked(address indexed user, uint256 amount, uint256 time);
    // Event emitted when token is transferred to liquidityMining for adding liquidity
    event TokenTransferedToLiquidityMining(address indexed user, uint256 amount, uint256 time);

    modifier whenClaimStarted() {
        // verify the claiming was started
        require(claimStart != 0 && block.timestamp >= claimStart, "Claiming is not able now.");
        
        // execute the rest of the function
        _;
    }

    modifier onlyOwnerOrLiquidityMiningContract() {
        if(
            (
                liquidityMining == address(0) ||
                liquidityMining != _msgSender()
            ) &&
            (owner() != _msgSender())
        ) {
            revert("Invalid permission to call this function");
        }
        _;
    }

    constructor(address _token) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Token address cannot be zero.");

        token = IERC20(_token);

        // add empty element into claim info array for comfortable index
        claimInfos.push(ClaimInfo({
            user: address(0),
            amount: 0,
            remain: 0,
            claimed: 0
        }));
    }

    /******************************************************
                            Setter
    ******************************************************/

    /**
     * @notice Set the address of staking contract
     *
     * @param _staking The address of the staking contract
     */
    function setStakingContract(address _staking) external onlyOwner {
        // verify input argument
        require(address(_staking) != address(0), "Staking contract cannot be zero address.");

        staking = _staking;

        emit StakingContractAddressUpdated(msg.sender, staking, block.timestamp);
    }

    /**
     * @notice Set the address of liquidity mining contract
     *
     * @param _liquidityMining The address of the staking contract
     */
    function setLiquidityMiningContract(address _liquidityMining) external onlyOwner {
        // verify input argument
        require(address(_liquidityMining) != address(0), "Liquidity mining contract cannot be zero address.");

        liquidityMining = _liquidityMining;

        emit LiquidityMiningContractAddressUpdated(msg.sender, liquidityMining, block.timestamp);
    }

    /**
     * @notice Set the time to start claiming
     *
     * @param _claimStart The time to start claiming
     */
    function setClaimStart(uint256 _claimStart) external onlyOwnerOrLiquidityMiningContract {
        // verify input argument
        require(_claimStart >= block.timestamp, "Invalid time for start claiming.");

        claimStart = _claimStart;

        emit ClaimStartTimeUpdated(msg.sender, _claimStart);
    }

    /**
     * @notice Set the detail of entry that can claim token
     *
     * @dev allow claim 0 amount
     *
     * @param user address of the user
     * @param amount amount of the claim
     */
    function setClaim(address user, uint256 amount) external onlyOwnerOrLiquidityMiningContract {
        // verify input argument
        require(user != address(0), "User address cannot be zero.");

        uint256 previousAmount;

        uint256 index = claimInfoIndex[user];
        if (index > 0) {
            // update previous claim data
            ClaimInfo storage claimInfo = claimInfos[index];
            previousAmount = claimInfo.amount;
            claimInfo.amount = amount;
            claimInfo.claimed = 0;
            claimInfo.remain = amount;
        } else {
            // push new user's claim info
            previousAmount = 0;
            claimInfoIndex[user] = claimInfos.length;
            claimInfos.push(ClaimInfo({
                user: user,
                amount: amount,
                claimed: 0,
                remain: amount
            }));
        }

        emit ClaimInfoUpdated(user, previousAmount, amount, block.timestamp);
    }

    /**
     * @notice Set the batch of entry that can claim token
     *
     * @param users array of users' address
     * @param amounts array of users' claimable token amount
     */
    function setClaimBatch(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        // verify input argment arrays' length
        require(users.length != 0, "Invalid input array's length.");
        require(users.length <= MAX_BATCH_SET_CLAIM, "Invalid input array's length.");
        require(users.length == amounts.length, "The length of arrays for users and amounts should be same.");

        for(uint256 i = 0; i < users.length; ) {
            address user = users[i];
            // verify user's address is valid
            require(user != address(0), "User address cannot be zero.");
            uint256 amount = amounts[i];

            uint256 previousAmount;

            uint256 index = claimInfoIndex[user];
            if (index > 0) {
                // update previous claim data
                ClaimInfo storage claimInfo = claimInfos[index];
                previousAmount = claimInfo.amount;
                claimInfo.amount = amount;
                claimInfo.claimed = 0;
                claimInfo.remain = amount;
            } else {
                // push new user's claim info
                previousAmount = 0;
                claimInfoIndex[user] = claimInfos.length;
                claimInfos.push(ClaimInfo({
                    user: user,
                    amount: amount,
                    claimed: 0,
                    remain: amount
                }));
            }

            unchecked {
                ++i;
            }

            emit ClaimInfoUpdated(user, previousAmount, amount, block.timestamp);
        }
    }

    /*****************************************************
                           external
    *****************************************************/

    /**
     * @notice Deposit token so that user can claim their token from this contract
     *
     * @dev only owner can call this function
     *
     * @param amount the amount to be deposited
     */
    function deposit(uint256 amount) external onlyOwner {
        // verify input argument
        require(amount > 0, "Cannot deposit zero amount");

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Withdraw deposited token back
     *
     * @dev only owner can call this function
     *
     * @param amount the amount to be withdrawn
     */
    function withdraw(uint256 amount) external onlyOwner {
        // verify input argument
        require(amount > 0, "Cannot withdraw zero amount");

        token.safeTransfer(owner(), amount);

        emit Withdrawed(owner(), amount, block.timestamp);
    }

    /**
     * @notice User claims their purchased token to the particular address
     *
     * @dev users can claim only after claim is started
     *
     * @param beneficiary the address that will receives claimed token
     * @param amount the amount to be claimed
     */
    function claim(address beneficiary, uint256 amount) external whenClaimStarted {
        // verify input argument
        require(amount != 0, "Cannot claim zero amount");
        require(beneficiary != address(0), "Cannot claim to zero address");
        // verify claimable amount
        uint256 index = claimInfoIndex[msg.sender];
        ClaimInfo storage claimInfo = claimInfos[index];
        require(amount <= getClaimableAmount(msg.sender), "Insufficient claimable amount");

        claimInfo.remain -= amount;
        claimInfo.claimed += amount;

        token.safeTransfer(beneficiary, amount);

        emit Claimed(msg.sender, beneficiary, amount, block.timestamp);
    }

    /**
     * @notice User can stake their claimable token to the staking contract directly
     *
     * @dev users can stake their token even when staking is disabled through this function
     *
     * @param amount the amount to be staken
     * @param durationInMonths the duration to be staken in months
     */
    function stake(uint256 amount, uint256 durationInMonths) external {
        // verify input argument
        require(amount != 0, "Cannot claim zero amount");
        // verify staking contract address is valid
        require(staking != address(0), "Invalid staking address");
        // verify claimable amount
        uint256 index = claimInfoIndex[msg.sender];
        ClaimInfo storage claimInfo = claimInfos[index];
        require(amount <= claimInfo.remain, "Insufficient claimable amount");

        claimInfo.remain -= amount;
        bool success = token.approve(staking, amount);
        require(success, "Approve failed");

        IStaking(staking).stakeFromClaiming(msg.sender, amount, durationInMonths);

        emit Staked(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice transfer sale tokens to liquidity mining contract for adding liquidity
     *
     * @dev callable only from liquidity minig contract itself
     *
     * @param amount token amount to be transferred
     */
    function transferTokenToLiquidityMining(uint256 amount) external {
        // verify input argument
        require(amount != 0, "Cannot transfer zero amount");
        // verify liquidity mining contract
        require(liquidityMining != address(0) && liquidityMining == msg.sender, "Only liquidity mining contract can call this function");

        token.safeTransfer(liquidityMining, amount);

        emit TokenTransferedToLiquidityMining(msg.sender, amount, block.timestamp);
    }

    /*****************************************************
                            Getter
    *****************************************************/
    
    /**
     * @notice Get the total deposited amount of token by the owner
     */
    function getTotalDeposits() public view returns(uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Get the claimable amount of particular user
     *
     * @param user the address of user to need to get the claimable amount
     */
    function getClaimableAmount(address user) public view returns(uint256 amount) {
        uint256 index = claimInfoIndex[user];
        ClaimInfo memory claimInfo = claimInfos[index];
        
        uint256 vestingAmount = getClaimaVestingAmount(user);

        amount = vestingAmount > claimInfo.remain ? claimInfo.remain : vestingAmount;
    }

    /**
     * @notice Get the claimable vesting amount of particular user
     *
     * @param user the address of user to need to get the detail
     */
    function getClaimaVestingAmount(address user) public view returns(uint256) {
        uint256 index = claimInfoIndex[user];
        ClaimInfo memory claimInfo = claimInfos[index];
        // return zero value if claiming is unable
        if (claimStart == 0 || block.timestamp < claimStart) return 0;

        uint256 monthIndex = (block.timestamp - claimStart) / 30 days + 1;
        monthIndex = monthIndex <= 4 ? monthIndex : 4;
        uint256 vestingAvailable = claimInfo.amount * monthIndex * VESTING_PER_MONTH / DENOMINATOR;

        if (vestingAvailable <= claimInfo.claimed) return 0;

        return vestingAvailable - claimInfo.claimed;
    }

    /**
     * @notice get the actual claims array length
     * 
     * @dev avoid first empty element of the array
     */
    function getClaimInfoLength() public view returns(uint256) {
        return claimInfos.length - 1;
    }

    /**
     * @notice get the index in claim info array of particular user
     * 
     * @param user address to get the index of claim info
     */
    function getClaimInfoIndex(address user) public view returns(uint256) {
        return claimInfoIndex[user];
    }

    /**
     * @notice get the claim info of particular user address
     *
     * @param user address of user to get the info
     */
    function getClaimInfo(address user) public view returns(uint256 amount, uint256 claimed, uint256 remain) {
        uint256 index = claimInfoIndex[user];

        amount = claimInfos[index].amount;
        claimed = claimInfos[index].claimed;
        remain = claimInfos[index].remain;
    }

    /**
     * @notice get the claim info at the particular index
     * 
     * @dev avoid first empty element of the array
     *
     * @param index index to get the claim info
     */
    function getClaimInfo(uint256 index) public view returns(address user, uint256 amount, uint256 claimed, uint256 remain) {
        require(index != 0, "Invalid start index"); // should avoid first empty element
        require(index < claimInfos.length, "Invalid index value");

        return (
            claimInfos[index].user,
            claimInfos[index].amount,
            claimInfos[index].claimed,
            claimInfos[index].remain
        );
    }

    /**
     * @notice get the array of claim info between particular indexes
     * 
     * @dev avoid first empty element of the array
     *
     * @param fromIndex start index; should be greater than 0 (to avoid first empty element)
     * @param toIndex end index
     */

    function getClaimInfoArray(uint256 fromIndex, uint256 toIndex) public view returns(ClaimInfo[] memory) {
        uint256 length = claimInfos.length;
        require(fromIndex > 0, "Invalid start index"); // should avoid first empty element
        require(fromIndex <= toIndex, "Invalid indexes.");
        require(toIndex < length, "Index cannot be over the length of staking");

        ClaimInfo[] memory returnClaimInfo = new ClaimInfo[](toIndex - fromIndex + 1);
        for (uint256 i = fromIndex; i <= toIndex; ) {
            returnClaimInfo[i - fromIndex] = claimInfos[i];
            unchecked {
                ++i;
            }
        }

        return returnClaimInfo;
    }
}