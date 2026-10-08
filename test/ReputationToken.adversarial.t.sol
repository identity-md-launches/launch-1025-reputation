// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReputationToken} from "../src/ReputationToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestSupport} from "./helpers/TestSupport.sol";

/// @dev Complements the original suite with allowance boundaries, retries and failure atomicity.
/// forge-config: default.fuzz.runs = 1000
contract ReputationTokenAdversarialTest is TestSupport {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    ReputationToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new ReputationToken();
    }

    function test_smallestUnitMakesAnExactRoundTrip() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferFailsWithoutOverflowOrMinting() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        _assertUnspentSupply();
    }

    function test_infiniteAllowanceDoesNotBypassBalanceAtMaximumAmount() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        _assertUnspentSupply();
    }

    function test_largestFiniteAllowanceIsDecremented() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceRejectsMaximumSpend() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, type(uint256).max - 1, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 1);
        _assertUnspentSupply();
    }

    function test_infiniteApprovalCanBeRevokedAndReplaced() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerCallingTransferFromStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        _assertUnspentSupply();

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroDelegatedTransferEmitsAndPreservesFiniteApproval() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 0));
        assertEq(token.allowance(address(this), SPENDER), 1);
        _assertUnspentSupply();
    }

    function test_exhaustedAllowanceCannotReplaySuccessfulSpend() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSpenderCannotBeApprovedEvenForZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        _assertUnspentSupply();
    }

    function test_infiniteApprovalCannotBurnThroughZeroRecipient() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        _assertUnspentSupply();
    }

    function test_zeroSenderCannotReachMintThroughTransfer() public {
        // A synthetic caller exercises the inherited invalid-sender guard directly.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 1);
        _assertUnspentSupply();
    }

    function test_zeroSenderCannotCreateApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, type(uint256).max);
        assertEq(token.allowance(address(0), SPENDER), 0);
        _assertUnspentSupply();
    }

    function testFuzz_transferFromInsufficientAllowanceIsAtomic(uint256 approvalSeed, uint256 amountSeed) public {
        uint256 approved = bound(approvalSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, approved + 1, SUPPLY);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        _assertUnspentSupply();
    }

    function testFuzz_transferFromInsufficientBalanceIsAtomic(uint256 balanceSeed, uint256 amountSeed, bool infinite)
        public
    {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalOverwriteIsExactAndIdempotent(uint256 initial, uint256 replacement) public {
        // An empty owner may approve more than its balance, including either uint256 boundary.
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, initial));
        assertEq(token.allowance(ALICE, SPENDER), initial);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.allowance(BOB, SPENDER), 0);
        _assertUnspentSupply();
    }

    function testFuzz_allowancesAreIsolatedByOwner(uint256 aliceApproval, uint256 bobApproval, uint256 amountSeed)
        public
    {
        assertTrue(token.transfer(ALICE, SUPPLY / 2));
        assertTrue(token.transfer(BOB, SUPPLY / 2));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, aliceApproval));
        vm.prank(BOB);
        assertTrue(token.approve(SPENDER, bobApproval));
        uint256 limit = aliceApproval < SUPPLY / 2 ? aliceApproval : SUPPLY / 2;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, SPENDER, amount));
        assertEq(
            token.allowance(ALICE, SPENDER), aliceApproval == type(uint256).max ? aliceApproval : aliceApproval - amount
        );
        assertEq(token.allowance(BOB, SPENDER), bobApproval);
        assertEq(token.balanceOf(ALICE), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(BOB), SUPPLY / 2);
        assertEq(token.balanceOf(SPENDER), amount);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedRoundTripRestoresBalancesButConsumesFiniteApproval(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, address(this), amount));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        _assertUnspentSupply();
    }

    function _assertUnspentSupply() internal view {
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
