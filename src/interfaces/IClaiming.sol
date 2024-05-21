pragma solidity ^0.8.20;

interface IClaiming {
    function setClaim(address, uint256) external;

    function getClaimInfoIndex(address) external view returns(uint256);

    function getClaimableAmount(address) external view returns(uint256);

    function transferTokenForAddingLiquidity(uint256) external;
}
