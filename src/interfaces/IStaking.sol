pragma solidity ^0.8.20;

interface IStaking {
    function stakeFromClaiming(address, uint256, uint256) external;
}
