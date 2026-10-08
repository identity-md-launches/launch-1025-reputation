// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReputationToken} from "../src/ReputationToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestSupport} from "./helpers/TestSupport.sol";

contract AdminFactoryFixture {
    function deployAndNominate(address intendedOwner) external returns (ReputationToken token) {
        token = new ReputationToken();
        token.transferOwnership(intendedOwner);
    }
}

contract ReputationTokenControlsTest is TestSupport {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    ReputationToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event FeeUpdated(uint256 previousFeeBps, uint256 newFeeBps);
    event Paused(address account);
    event Unpaused(address account);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        token = new ReputationToken();
    }

    function test_constructorEmitsOwnershipAndUntaxedMint() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(0), address(this));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        ReputationToken deployed = new ReputationToken();
        assertTrue(deployed.pendingOwner() == address(0));
        assertEq(deployed.BPS_DENOMINATOR(), 10_000);
        assertEq(deployed.feeBps(), 50);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_feeRoundsDownAtBaseUnitBoundaries() public {
        token.transfer(ALICE, 199);
        assertEq(token.totalSupply(), SUPPLY);
        token.transfer(ALICE, 200);
        token.transfer(ALICE, 201);
        token.transfer(ALICE, 399);
        token.transfer(ALICE, 400);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1399);
        assertEq(token.balanceOf(ALICE), 1394);
        assertEq(token.totalSupply(), SUPPLY - 5);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_ownerSetsFeeWithEventAndBothTransferPathsUseIt() public {
        vm.expectEmit(false, false, false, true, address(token));
        emit FeeUpdated(50, 250);
        token.setFeeBps(250);
        token.transfer(ALICE, 10 ether);
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 10 ether);
        assertEq(token.feeBps(), 250);
        assertEq(token.balanceOf(ALICE), 9.75 ether);
        assertEq(token.balanceOf(BOB), 9.75 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY - 0.5 ether);
    }

    function test_zeroFeeDisablesBurnOnBothTransferPaths() public {
        token.setFeeBps(0);
        token.transfer(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, SUPPLY);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_maximumFeeCanBurnEntireSupply() public {
        token.setFeeBps(10_000);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(0), SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 0);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        token.transfer(ALICE, 0);
    }

    function test_maximumFeeStillRequiresGrossBalanceOnSelfTransfer() public {
        token.setFeeBps(10_000);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.totalSupply(), SUPPLY);
        token.transfer(address(this), SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_netAllowanceIsInsufficientForGrossTransfer() public {
        token.approve(SPENDER, 99.5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 99.5 ether, 100 ether)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 100 ether);
        assertEq(token.allowance(address(this), SPENDER), 99.5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidFeeRevertsWithoutChangingRate(uint256 seed) public {
        uint256 invalid = bound(seed, 10_001, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.InvalidFee.selector, invalid));
        token.setFeeBps(invalid);
        assertEq(token.feeBps(), 50);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_nonOwnerCannotSetFee(uint256 fee) public {
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, ALICE));
        vm.prank(ALICE);
        token.setFeeBps(fee);
        assertEq(token.feeBps(), 50);
    }

    function testFuzz_feeAccountingAcrossRatesAndTransferPaths(
        uint256 feeSeed,
        uint256 amountSeed,
        bool delegated,
        bool selfTransfer,
        bool infinite
    ) public {
        uint256 rate = bound(feeSeed, 0, 10_000);
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        // Independent quotient/remainder formula also checks floor rounding.
        uint256 burned = (amount / 10_000) * rate + ((amount % 10_000) * rate) / 10_000;
        address recipient = selfTransfer ? address(this) : ALICE;
        token.setFeeBps(rate);
        if (delegated) {
            token.approve(SPENDER, infinite ? type(uint256).max : amount);
            vm.prank(SPENDER);
            token.transferFrom(address(this), recipient, amount);
            assertEq(token.allowance(address(this), SPENDER), infinite ? type(uint256).max : 0);
        } else {
            token.transfer(recipient, amount);
        }
        assertEq(token.totalSupply(), SUPPLY - burned);
        assertEq(token.balanceOf(address(this)), selfTransfer ? SUPPLY - burned : SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), selfTransfer ? 0 : amount - burned);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_pauseUnpauseEventsAndRepeatedTransitions() public {
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.ExpectedPause.selector));
        token.unpause();
        vm.expectEmit(false, false, false, true, address(token));
        emit Paused(address(this));
        token.pause();
        assertTrue(token.paused());
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        token.pause();
        vm.expectEmit(false, false, false, true, address(token));
        emit Unpaused(address(this));
        token.unpause();
        assertTrue(!token.paused());
        token.transfer(ALICE, 1 ether);
        assertEq(token.balanceOf(ALICE), 0.995 ether);
    }

    function test_nonOwnerCannotPauseOrUnpause() public {
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, ALICE));
        vm.prank(ALICE);
        token.pause();
        assertTrue(!token.paused());
        token.pause();
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, ALICE));
        vm.prank(ALICE);
        token.unpause();
        assertTrue(token.paused());
    }

    function test_pauseBlocksOwnerHolderSelfAndZeroTransfers() public {
        token.transfer(ALICE, 100 ether);
        token.pause();
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        vm.prank(ALICE);
        token.transfer(BOB, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        vm.prank(ALICE);
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        vm.prank(BOB);
        token.transfer(ALICE, 0);
        assertEq(token.balanceOf(ALICE), 99.5 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.totalSupply(), SUPPLY - 0.5 ether);
    }

    function test_pausedTransferFromRollsBackFiniteAndInfiniteAllowance() public {
        token.approve(SPENDER, 100 ether);
        token.approve(BOB, type(uint256).max);
        token.pause();
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.EnforcedPause.selector));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 0);
        assertEq(token.allowance(address(this), SPENDER), 100 ether);
        assertEq(token.allowance(address(this), BOB), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        token.unpause();
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 100 ether);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 99.5 ether);
    }

    function test_approvalsRevocationsAndFeeChangesRemainAvailableWhilePaused() public {
        token.pause();
        vm.prank(ALICE);
        token.approve(SPENDER, 100 ether);
        assertEq(token.allowance(ALICE, SPENDER), 100 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        token.setFeeBps(100);
        token.unpause();
        token.transfer(ALICE, 100 ether);
        assertEq(token.balanceOf(ALICE), 99 ether);
        assertEq(token.totalSupply(), SUPPLY - 1 ether);
    }

    function test_ownershipHandoverWhilePausedAndOldOwnerLosesAllPowers() public {
        token.pause();
        vm.expectEmit(true, true, false, true, address(token));
        emit OwnershipTransferStarted(address(this), ALICE);
        token.transferOwnership(ALICE);
        assertTrue(token.owner() == address(this));
        assertTrue(token.pendingOwner() == ALICE);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, ALICE));
        vm.prank(ALICE);
        token.setFeeBps(100);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, ALICE));
        vm.prank(ALICE);
        token.unpause();
        vm.expectEmit(true, true, false, true, address(token));
        emit OwnershipTransferred(address(this), ALICE);
        vm.prank(ALICE);
        token.acceptOwnership();
        assertTrue(token.owner() == ALICE);
        assertTrue(token.pendingOwner() == address(0));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, address(this)));
        token.setFeeBps(100);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, address(this)));
        token.pause();
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, address(this)));
        token.unpause();
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, address(this)));
        token.transferOwnership(BOB);
        vm.prank(ALICE);
        token.setFeeBps(100);
        vm.prank(ALICE);
        token.unpause();
        token.transfer(BOB, 100 ether);
        assertEq(token.balanceOf(BOB), 99 ether);
        vm.prank(ALICE);
        token.pause();
        assertTrue(token.paused());
    }

    function test_invalidAndUnauthorizedOwnershipOperationsRevert() public {
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.InvalidOwner.selector, address(0)));
        token.transferOwnership(address(0));
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.InvalidOwner.selector, address(token)));
        token.transferOwnership(address(token));
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedOwner.selector, ALICE));
        vm.prank(ALICE);
        token.transferOwnership(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedPendingOwner.selector, ALICE));
        vm.prank(ALICE);
        token.acceptOwnership();
        token.transferOwnership(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedPendingOwner.selector, BOB));
        vm.prank(BOB);
        token.acceptOwnership();
        assertTrue(token.owner() == address(this));
        assertTrue(token.pendingOwner() == ALICE);
    }

    function test_replacedNomineeCannotAcceptAndAcceptanceCannotReplay() public {
        token.transferOwnership(ALICE);
        token.transferOwnership(BOB);
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedPendingOwner.selector, ALICE));
        vm.prank(ALICE);
        token.acceptOwnership();
        vm.prank(BOB);
        token.acceptOwnership();
        vm.expectRevert(abi.encodeWithSelector(ReputationToken.UnauthorizedPendingOwner.selector, BOB));
        vm.prank(BOB);
        token.acceptOwnership();
        assertTrue(token.owner() == BOB);
        assertTrue(token.pendingOwner() == address(0));
    }

    function test_factoryCanNominateAnOperationalOwner() public {
        AdminFactoryFixture factory = new AdminFactoryFixture();
        ReputationToken deployed = factory.deployAndNominate(ALICE);
        assertTrue(deployed.owner() == address(factory));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        vm.prank(ALICE);
        deployed.acceptOwnership();
        vm.prank(ALICE);
        deployed.setFeeBps(25);
        vm.prank(ALICE);
        deployed.pause();
        assertTrue(deployed.owner() == ALICE);
        assertEq(deployed.feeBps(), 25);
        assertTrue(deployed.paused());
    }
}
