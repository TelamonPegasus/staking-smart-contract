// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

contract BaseTest is Test {
    uint256 public mainnetFork;

    function setUp() public {
        mainnetFork = vm.createSelectFork("avalanche");
    }
}