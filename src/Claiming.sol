pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Staking.sol";

contract Claiming is Ownable {
    using SafeERC20 for IERC20;

    // presale token
    IERC20 public token;
    // staking contract
    address public staking;
    // claiming start date
    uint256 public claimStart;

    // maximum array length for set batch claim info
    uint256 public MAX_BATCH_SET_CLAIM = 1_000;

    // purchased presale token
    mapping(address => uint256) public claims;

    /* ========== EVENTS ========== */
    // Event emitted when a owner deposits token
    event Deposited(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a owner withdraws token
    event Withdrawed(address indexed user, uint256 amount, uint256 time);
    // Event emitted when a owner updates the time to start claiming
    event ClaimStartTimeUpdated(address indexed user, uint256 claimStartTime);
    // Event emitted when a owner updates the time to start claiming
    event ClaimInfoUpdated(address indexed user, uint256 previousAmount, uint256 amount, uint256 time);
    // Event emitted when a user claimed his token
    event Claimed(address indexed user, address indexed beneficiary, uint256 amount, uint256 time);
    // Event emitted whan a user stake directly without 
    event Staked(address indexed user, uint256 amount, uint256 time);

    modifier whenClaimStarted() {
        // verify the claiming was started
        require(claimStart != 0 && block.timestamp > claimStart, "Claiming is not able now.");
        
        // execute the rest of the function
        _;
    }

    constructor(address _token, address _staking) Ownable(msg.sender) {
        // verify input argument
        require(_token != address(0), "Token address cannot be zero.");
        require(_staking != address(_staking), "Staking contract cannot be zero address");

        token = IERC20(_token);
        staking = _staking;
    }

    /******************************************************
                            Setter
    ******************************************************/

    /**
     * @notice Set the token address
     * 
     * @param _token The address of the token 
     */
    function setToken(address _token) external onlyOwner {
        // verify input argument
        require(_token != address(0), "Token address cannot be zero.");

        token = IERC20(_token);
    }

    /**
     * @notice Set the address of staking contract
     *
     * @param _staking The address of the staking contract
     */
    function setStakingContract(address _staking) external onlyOwner {
        // verify input argument
        require(address(token) != address(0), "Staking contract cannot be zero address.");

        staking = _staking;
    }

    /**
     * @notice Set the time to start claiming
     *
     * @param _claimStart The time to start claiming
     */
    function setClaimStart(uint256 _claimStart) external onlyOwner {
        // verify input argument
        require(_claimStart > block.timestamp, "Invalid time for start claiming.");

        claimStart = _claimStart;

        emit ClaimStartTimeUpdated(msg.sender, _claimStart);
    }

    /**
     * @notice Set the detail of entry that can claim token
     *
     * @param user address of the user
     * @param amount amount of the claim
     */
    function setClaim(address user, uint256 amount) external onlyOwner {
        // verify input argument
        require(user != address(0), "User address cannot be zero.");

        uint256 previousAmount = claims[user];
        claims[user] = amount;

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
        require(users.length <= MAX_BATCH_SET_CLAIM, "Invalid input array's length .");
        require(users.length == amounts.length, "The length of arrays for users and amounts should be same.");

        for(uint256 i = 0; i < users.length; ) {
            address user = users[i];
            // verify user's address is valid
            require(user != address(0), "User address cannot be zero.");
            uint256 amount = amounts[i];

            uint256 previousAmount = claims[user];
            claims[user] = amount;

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
        require(amount > 0, "Cannot deposit zero amount.");

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
        require(amount <= claims[msg.sender], "Insufficient claimable amount");

        claims[msg.sender] -= amount;

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
        require(amount <= claims[msg.sender], "Insufficient claimable amount");

        claims[msg.sender] -= amount;
        token.approve(staking, amount);

        Staking(staking).stakeFromClaiming(msg.sender, amount, durationInMonths);

        emit Staked(msg.sender, amount, block.timestamp);
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
     * @param user the address of user to need to get the detail
     */
    function getClaimableAmount(address user) public view returns(uint256) {
        return claims[user];
    }
}