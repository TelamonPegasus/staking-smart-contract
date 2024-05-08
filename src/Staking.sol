// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking is Ownable {
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

    // Mapping to track user balances
	mapping(address => UserStake[]) private userStakes;

    /* ========== EVENTS ========== */
	// Event emitted when a user stakes token
	event Staked(address indexed user, uint256 amount, uint256 time);
	// Event emitted when a user withdraws token
	event Withdrawed(address indexed user, uint256 amount, uint256 time);
	// Event emitted when a user claims reward token
	event Claimed(address indexed user, uint256 amount, uint256 time);

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
    function stake(uint256 amount, uint256 durationInMonths) external {
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
    
    function withdraw(index) external {
        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.amount > 0, "There is no staked token");

        // if the staking is not 
        if (block.timestamp < userStake.lockTime) {
            userStake.rewards = 0;
        }
		
        // transfer token from here to staker's wallet
        token.safeTransfer(msg.sender, amount);

        // emit an event
        emit Withdrawed(msg.sender, amount, block.timestamp);
    }

    function claimRewards(uint256 index) external {
        // verify input argument
        require(index < userStakes[msg.sender].length)
        // cannot claim before the stake fully matures
        require(isClaimableRewards(), "Cannot claim rewards before locking is over.");
        UserStake storage userStake = userStakes[msg.sender][index];
        // validate amount for reward token
        require(userStake.rewards > 0, "There is no claimable reward token.");

        uint256 rewards = userStake.rewards;
        userStake.rewards = 0;

        rewardToken.safeTransfer(msg.sender, rewards);

        // emit an event
        emit Claimed(msg.sender, rewards, block.timestamp);
    }

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

    function isClaimableRewards(index) public view returns(bool) {
        // verify input argument
        require(index <  userStakes[msg.sender].length, "Invalidate index for staked records.");

        return userStakes[msg.sender][index].lockTime <= block.timestamp;
    }

    // ******* getters ******** //

}
