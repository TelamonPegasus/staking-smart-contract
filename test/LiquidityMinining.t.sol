// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMining} from "../src/LiquidityMining.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BaseTest is Test {
    uint256 public mainnetFork;

    LiquidityMining public liquidityMining;
    MockERC20 public token;

    function setUp() public {
        mainnetFork = vm.createSelectFork("mainnet");

        token = new MockERC20();

        liquidityMining = new LiquidityMining(address(token));
    }


    function test_setTokenRevertZeroAddress() public {
        vm.expectRevert("Token address cannot be zero.");

        liquidityMining.setToken(address(0));
    }

    function test_setToken() public {
        MockERC20 newMockERC20 = new MockERC20();

        liquidityMining.setToken(address(newMockERC20));
        assertEq(address(liquidityMining.token()), address(newMockERC20));
    }
}