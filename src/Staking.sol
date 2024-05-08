// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking is Ownable {
	using SafeERC20 for IERC20;
    struct UserStake {
        uint256 amount;
        uint256 lockTime;
        uint256 rewards;
    }

    // Token being staked
    IERC20 public token;
    // Token being rewarded
    IERC20 public rewardToken;

	// Total supply of staked tokens
	uint256 public totalSupply;

    // Value that represents whether staking is possible or not
    bool public stakingEnabled;

    // Mapping to track user balances
	mapping(address => UserStake[]) private userStakes;

	modifier stakingEnabled(uint256 role) {
		// verify the staking enabled
		require(stakingEnabled, "Staking is not enabled.");

		// execute the rest of the function
		_;
	}

    /* ========== EVENTS ========== */
	// Event emitted when a user stakes token
	event Staked(address indexed user, uint256 amount, uint256 time);
	// Event emitted when a user withdraws token
	event Withdrawed(address indexed user, uint256 amount, uint256 time);
	// Event emitted when a user claims reward token
	event Claimed(address indexed user, uint256 amount, uint256 time);
	// Event emitted when tokens are recovered
	event Recovered(address indexed sender, address token, uint256 amount);

    /**
     * @dev Set the staking & reward token contract and owner of this smart contract.
     * 
     * @param _token token address to be staked
     * @param _rewardToken token address to be rewarded
     */
    constructor(address _token, address _rewardToken) Ownable(msg.sender) {
        token = IERC20(_token);
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @notice Stakes the token; the token is transferred from staker's wallet to this contract,
     * and the staking duration is calculated in months.
     * 
     * @param amount amount of token to be staked
     * @param durationInMonths duration of staking in months 
     */
    function stake(uint256 amount, uint256 durationInMonths) external stakingEnabled {
		// verify input argument
		require(amount > 0, "cannot stake 0");
        // validate duration in months
        require(durationInMonths > 0, "cannot stake for 0 days");
        require(durationInMonths <= 60, "cannot stake for over 5 years");

		// transfer token from staker's wallet
		token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 rewards = calculateRewards(amount, durationInMonths);
        uint256 lockTime = block.timestamp + (durationInMonths * 30 days);
        userStakes[msg.sender].push(UserStake({
            amount: amount,
            lockTime: lockTime,
            rewards: rewards
        }));

		// update total stake amount
		totalSupply += amount;

		// emit an event
		emit Staked(msg.sender, amount, block.timestamp);
	}
    
    /**
     * @notice Withdraw staked token
     * 
     * @dev when break the staking before time is up, the rewards will be removed
     *
     * @param index index of staking to withdraw
     */
    function withdraw(uint256 index) external {
        // verify input argument
        require(index < userStakes[msg.sender].length, "Invalid index of staking");
        
        UserStake storage userStake = userStakes[msg.sender][index];
        require(userStake.amount > 0, "There is no staked token");

        // remove rewards if it breaks the staking before time is up
        if (block.timestamp < userStake.lockTime) {
            userStake.rewards = 0;
        }

        uint256 amount = userStake.amount;
        userStake.amount = 0;

        // update the total stake amount
		totalSupply -= amount;
		
        // transfer token from here to staker's wallet
        token.safeTransfer(msg.sender, amount);

        // emit an event
        emit Withdrawed(msg.sender, amount, block.timestamp);
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

        rewardToken.safeTransfer(msg.sender, rewards);

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
    function calculateRewards(uint256 _principal, uint256 _durationInMonths) private pure returns (uint256) {
        if (_durationInMonths <= 3) {
            return _principal * 10 / 100;
        } else if (_durationInMonths <= 6) {
            return _principal * 25 / 100;
        } else if (_durationInMonths <= 9) {
            return _principal * 35 / 100;
        } else {
            return _principal * 50 / 100;
        }
    }

    /**
     * @notice Check a particular stake is still on the state of staking or not
     * 
     * @param staker address of staker
     * @param index index of staking to be checked
     *
     * @return 
     */
    function isStaked(address staker, uint256 index) public view returns(bool) {
        // verify input argument
        require(index <  userStakes[staker].length, "Invalidate index for staked records.");

        return userStakes[staker][index].lockTime > block.timestamp;
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

    /*****************************************************
                            Setter
    *****************************************************/

    /**
     * @notice Set the staking token
     * 
     * @dev Only owner can call this function; should check non-zero address
     * 
     * @param _token address of the staking token to be updated
     */
    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Staking token address cannot be zero address");

        token = IERC20(_token);
    }

    /**
     * @notice Set the reward token
     * 
     * @dev Only owner can call this function; should check non-zero address
     * 
     * @param _rewardToken address of the reward token to be updated
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Staking token address cannot be zero address");

        rewardToken = IERC20(_rewardToken);
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
    }
}
