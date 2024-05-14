pragma solidity ^0.8.20;

interface IClaiming {
    function getClaimInfoIndex(address) external view returns(uint256);
}
