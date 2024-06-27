// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking is Ownable {
    using SafeERC20 for IERC20;
    struct UserStake {
        uint256 amount;
        uint256 lockOn;
        uint256 lockEnd;
        uint256 rewards;
    }

    // Token being staked
    IERC20 public token;
    // Claiming contract address
    address public claiming;

    // Total supply of staked tokens
    uint256 public totalSupply;

    // Value that represents whether staking is possible or not
    bool public stakingEnabled;

    // Reward limit for restrict staking
    uint256 public rewardLimit;
    // Current reward amount which claimed or will claim
    uint256 public rewardAmount;

    uint256 public REWARD_RATE_1Q = 1_000;
    uint256 public REWARD_RATE_2Q = 2_500;
    uint256 public REWARD_RATE_3Q = 3_500;
    uint256 public REWARD_RATE_4Q = 5_000;
    uint256 public DENOMINATOR = 10_000;

    // Mapping to track user balances
    mapping(address => UserStake[]) private userStakes;

    modifier onlyWhenStakingEnabled() {
        // verify the staking enabled
        require(stakingEnabled, "Staking is not enabled.");

        // execute the rest of the function
        _;
    }

    /* ========== EVENTS ========== */
    // Event emitted when a user stakes token
    event Staked(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a user stakes token fron claiming directly
    event StakedDirectly(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a user withdraws token
    event Withdrawed(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a user claims reward token
    event Claimed(address indexed user, uint256 amount, uint256 time);
    // Event emitted when tokens are recovered
    event Recovered(address indexed sender, address token, uint256 amount);
    // Event emitted when claiming contract address was updated by the owner
    event ClaimingContractAddressUpdated(address indexed user, address claiming, uint256 time);
    // Event emitted when staking is enabled by the owner
    event StakingEnabled(address indexed user, uint256 time);
    // Event emitted when owner updates the reward limit
    event RewardLimitUpdated(address indexed user, uint256 amount, uint256 time);

    /**
     * @dev Set the staking & reward token contract and owner of this smart contract.
     * 
     * @param _token token address to be staked
     */
    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
    }

    /**
     * @notice Stakes the token; the token is transferred from staker's wallet to this contract,
     * and the staking duration is calculated in months.
     * 
     * @param amount amount of token to be staked
     * @param durationInMonths duration of staking in months 
     */
    function stake(uint256 amount, uint256 durationInMonths) external onlyWhenStakingEnabled {
        // verify input argument
        require(amount > 0, "cannot stake 0");
        // validate duration in months
        require(
            durationInMonths == 3 ||
            durationInMonths == 6 ||
            durationInMonths == 9 ||
            durationInMonths == 12,
            "Invalid duration for staking."
        );

        // transfer token from staker's wallet
        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 rewards = calculateRewards(amount, durationInMonths);
        // update the cumulative reward amount
        rewardAmount += rewards;
        // verify if reward amount is not over limit
        require(rewardAmount <= rewardLimit, "Overflow of reward limit");

        uint256 lockEnd = block.timestamp + (durationInMonths * 30 days);
        userStakes[msg.sender].push(UserStake({
            amount: amount,
            lockOn: block.timestamp,
            lockEnd: lockEnd,
            rewards: rewards
        }));

        // update total stake amount
        totalSupply += amount;

        // emit an event
        emit Staked(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice presale buyers can stake their claimable tokens before staking is enabled
     * only callable from claiming contract
     *
     * @param staker address of staker who has claimable token
     * @param amount amount of token to stake
     * @param durationInMonths duration of staking in months
     */
    function stakeFromClaiming(address staker, uint256 amount, uint256 durationInMonths) external {
        // verify caller is claiming contract
        require(msg.sender == claiming, "Only claiming contract can call this function");

        // validate duration in months
        require(
            durationInMonths == 3 ||
            durationInMonths == 6 ||
            durationInMonths == 9 ||
            durationInMonths == 12,
            "Invalid duration for staking."
        );

        // transfer token from staker's wallet
        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 rewards = calculateRewards(amount, durationInMonths);
        // update the cumulative reward amount
        rewardAmount += rewards;
        // verify if reward amount is not over limit
        require(rewardAmount <= rewardLimit, "Overflow of reward limit");

        uint256 lockEnd = block.timestamp + (durationInMonths * 30 days);
        userStakes[staker].push(UserStake({
            amount: amount,
            lockOn: block.timestamp,
            lockEnd: lockEnd,
            rewards: rewards
        }));

        // update total stake amount
        totalSupply += amount;

        // emit an event
        emit StakedDirectly(staker, amount, block.timestamp);
    }
    
    /**
     * @notice Withdraw staked token
     * 
     * @dev when break the staking before time is up, the rewards will be removed
     *
     * @param index index of staking to withdraw
     */
    function withdraw(uint256 index) external onlyWhenStakingEnabled {
        // verify input argument
        require(index < userStakes[msg.sender].length, "Invalid index of staking");
        
        _withdraw(msg.sender, index);
    }

    /**
     * @notice withdraw all staked token;
     * it is recommended to use withdrawBatch function than this.
     * 
     * @param onlyClaimable bool value that represents whether will withdraw only claimable staking or not
     */
    function withdrawAll(bool onlyClaimable) external onlyWhenStakingEnabled {
        uint256 length = numStakes(msg.sender);
        require(length > 0, "You didn't stake anything");

        _withdrawBatch(msg.sender, 0, length-1, onlyClaimable);
    }

    /**
     * @notice withdraw staked token between pointed indexes.
     * 
     * @param onlyClaimable bool value that represents whether will withdraw only claimable staking or not
     */
    function withdrawBatch(uint256 fromIndex, uint256 toIndex, bool onlyClaimable) external onlyWhenStakingEnabled {
        uint256 length = numStakes(msg.sender);
        require(length > 0, "You didn't stake anything");
        require(fromIndex <= toIndex, "Invalid indexes.");
        require(toIndex < length, "Index cannot be over the length of staking");

        _withdrawBatch(msg.sender, fromIndex, toIndex, onlyClaimable);
    }

    function _withdrawBatch(address staker, uint256 _fromIndex, uint256 _toIndex, bool _onlyClaimable) private {
        for (uint256 i = _fromIndex; i <= _toIndex; ) {
            if (_onlyClaimable && isStaked(staker, i)) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (userStakes[staker][i].amount > 0) {
                _withdraw(staker, i);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _withdraw(address staker, uint256 index) private returns(uint256) {
        UserStake storage userStake = userStakes[staker][index];
        require(userStake.amount > 0, "There is no staked token");

        // remove rewards if it breaks the staking before time is up
        // if (block.timestamp < userStake.lockEnd) {
        //     // decrease the cumulative reward amount
        //     rewardAmount -= userStake.rewards;
        //     // remove rewards of staker
        //     userStake.rewards = 0;
        // }
        require(block.timestamp >= userStake.lockEnd, "Unable to withdraw before locking is over");

        uint256 amount = userStake.amount;
        userStake.amount = 0;

        // update the total stake amount
        totalSupply -= amount;

        // transfer token from here to staker's wallet
        token.safeTransfer(staker, amount);

        // emit an event
        emit Withdrawed(staker, amount, block.timestamp);

        return amount;
    }

    /**
     * @notice Claim the rewards about the staked token
     * 
     * @dev cannot claim the rewards for the not matured staking
     * 
     * @param index index of staking to claim rewards 
     */
    function claimRewards(uint256 index) external {
        // verify input argument
        require(index < userStakes[msg.sender].length, "Invalid index of staking");
        // cannot claim before the stake fully matures
        require(!isStaked(msg.sender, index), "Cannot claim rewards before locking is over.");
        UserStake storage userStake = userStakes[msg.sender][index];
        // validate amount for reward token
        require(userStake.rewards > 0, "There is no claimable reward token.");

        uint256 rewards = userStake.rewards;
        userStake.rewards = 0;

        token.safeTransfer(msg.sender, rewards); // transfer rewards

        // emit an event
        emit Claimed(msg.sender, rewards, block.timestamp);
    }

    /**
     * @notice Calculate the amount of reward token based on the staking amount
     * 
     * @param _principal amount to be staked
     * @param _durationInMonths duration to be staked in months
     *
     * @return amount of reward token
     */
    function calculateRewards(uint256 _principal, uint256 _durationInMonths) private view returns (uint256) {
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

    /**
     * @notice Check a particular stake is still on the state of staking or not
     * 
     * @param staker address of staker
     * @param index index of staking to be checked
     */
    function isStaked(address staker, uint256 index) public view returns(bool) {
        // verify input argument
        require(index <  userStakes[staker].length, "Invalid index for staked records.");

        return userStakes[staker][index].lockEnd > block.timestamp;
    }

    /**
     * @dev Recovers ERC20 tokens accidentally sent to the contract
     *
     * @param _token Address of the ERC20 token to recover
     * @param amount Amount of tokens to recover
     */
    function recoverERC20(address _token, uint256 amount) external onlyOwner {
        // make sure owner won't withdraw stake token
        require(address(_token) != address(token), "cannot withdraw the staking token");

        // transfer token to owner account
        IERC20(_token).safeTransfer(owner(), amount);

        // emit an event
        emit Recovered(msg.sender, address(_token), amount);
    }

    /*****************************************************
                            Getter
    *****************************************************/

    /**
     * @notice How many stakes a particular address has done
     *
     * @param staker an address to query number of times it staked
     * @return number of times a particular address has staked
     */
    function numStakes(address staker) public view returns(uint256) {
        return userStakes[staker].length;
    }

    /**
     * @notice Get the info of a particular staking
     * 
     * @param staker address of user to get the staking info
     * @param index index of staking to get the detail
     */
    function getStakeInfo(address staker, uint256 index) public view returns(uint256, uint256, uint256, uint256) {
        // verify input argument
        require(index < userStakes[staker].length, "Invalid index for staked records.");

        UserStake storage userStake = userStakes[staker][index];
        return (
            userStake.amount,
            userStake.lockOn,
            userStake.lockEnd,
            userStake.rewards
        );
    }

    /**
     * @notice Get the info of a particular staking
     * 
     * @param staker address of user to get the staking info
     */
    function getStakeInfoArray(address staker) public view returns(UserStake[] memory) {
        uint256 length = numStakes(staker);
        UserStake[] memory userStakeArray = new UserStake[](length);

        for (uint256 i = 0; i < length;) {
            userStakeArray[i] = userStakes[staker][i];

            unchecked {
                ++i;
            }
        }

        return userStakeArray;
    }

    function getStakeInfoArray(address staker, uint256 fromIndex, uint256 toIndex) public view returns(UserStake[] memory) {
        require(toIndex >= fromIndex, "Invalid order of indexes");

        uint256 length = numStakes(staker);
        if (fromIndex >= length) return new UserStake[](0);
        
        toIndex = toIndex >= length ? length - 1 : toIndex;
        
        UserStake[] memory userStakeArray = new UserStake[](toIndex - fromIndex + 1);
        for (uint256 i = fromIndex; i <= toIndex;) {
            userStakeArray[i - fromIndex] = userStakes[staker][i];

            unchecked {
                ++i;
            }
        }

        return userStakeArray;
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

        emit ClaimingContractAddressUpdated(msg.sender, claiming, block.timestamp);
    }

    /**
     * @notice Enable staking; this is called by only owner.
     * Owner will enable staking as soon as presale is over.
     * 
     * @dev Once staking become enable, cannot disable it back again.
     */
    function setStakingEnabled() external onlyOwner {
        require(!stakingEnabled, "Staking is already enabled");

        stakingEnabled = true;

        emit StakingEnabled(msg.sender, block.timestamp);
    }

    /**
     * @notice Set the reward limit amount to restrict staking
     *
     * @dev only owner can call this funciton; able to set zero value
     *
     * @param _rewardLimit amount of reward limit to be set
     */
    function setRewardLimit(uint256 _rewardLimit) external onlyOwner {
        rewardLimit = _rewardLimit;

        emit RewardLimitUpdated(msg.sender, rewardLimit, block.timestamp);
    }
}
