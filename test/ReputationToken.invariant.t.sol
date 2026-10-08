// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReputationToken} from "../src/ReputationToken.sol";
import {TestSupport} from "./helpers/TestSupport.sol";

/// @dev An independent balance/allowance model across four actors and randomized action sequences.
contract ReputationHandler is TestSupport {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ReputationToken public immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new ReputationToken();
        assertTrue(token.transfer(actors[0], SUPPLY));
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = amountSeed % (expectedBalance[from] + 1);
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 amount = amountSeed % 3 == 0 ? type(uint256).max : amountSeed % (SUPPLY + 1);
        expectedAllowance[owner][spender] = amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 approved = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < approved ? expectedBalance[from] : approved;
        uint256 amount = amountSeed % (limit + 1);
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
    }
}

contract ReputationTokenInvariantTest is TestSupport {
    ReputationHandler internal handler;
    ReputationToken internal token;

    function setUp() public {
        handler = new ReputationHandler();
        token = handler.token();
    }

    /// @dev Foundry's invariant runner discovers this target list without forge-std.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_supplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
