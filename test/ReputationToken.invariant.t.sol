// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReputationToken} from "../src/ReputationToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 choice = amountSeed % 5;
        uint256 amount = choice == 0
            ? 0
            : choice == 1 ? type(uint256).max : choice == 2 ? type(uint256).max - 1 : bound(amountSeed, 0, SUPPLY);
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 approved = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < approved ? expectedBalance[from] : approved;
        uint256 amount = _amount(amountSeed, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    // Expected failures are caught explicitly. They must leave the model unchanged, and any
    // unexpected revert (including a failed assertion) fails the invariant campaign.
    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function transferFromOverAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed)
        external
    {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 approved = expectedAllowance[from][spender];
        if (approved == type(uint256).max) {
            approved -= 1;
            _approve(from, spender, approved);
        }
        uint256 amount = bound(amountSeed, approved + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function transferFromOverBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _approve(from, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        _approve(from, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
    }

    function revokeAndAttemptSpend(uint256 fromSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        _approve(from, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(from, spender, 1);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 fromIndex = fromSeed % 4;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % 3) % 4];
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        // Check the outward leg too: a broken transfer must not be hidden by its inverse.
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // No model updates: a fee-free round trip restores every balance and allowance.
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _amount(uint256 seed, uint256 maximum) internal pure returns (uint256) {
        // Hit empty, full and smallest-unit operations often, as well as intermediate values.
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum;
        if (seed % 4 == 2) return maximum == 0 ? 0 : 1;
        return bound(seed, 0, maximum);
    }
}

/// @dev Only the handler is targeted; all reachable holders are in its closed actor set.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
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
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_metadataRemainsFixed() public view {
        assertEq(token.name(), "REPUTATION");
        assertEq(token.symbol(), "REP");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
    }
}
