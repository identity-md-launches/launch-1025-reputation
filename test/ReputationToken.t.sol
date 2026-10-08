// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReputationToken} from "../src/ReputationToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestSupport} from "./helpers/TestSupport.sol";

contract FactoryFixture {
    function deploy(bytes32 salt) external returns (ReputationToken) {
        return new ReputationToken{salt: salt}();
    }
}

contract ReputationTokenTest is TestSupport {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    ReputationToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new ReputationToken();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "REPUTATION");
        assertEq(token.symbol(), "REP");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new ReputationToken();
    }

    function test_create2MintsToFactoryRatherThanTransactionOrigin() public {
        FactoryFixture factory = new FactoryFixture();
        ReputationToken deployed = factory.deploy(keccak256("REP factory deployment"));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 25 ether);
        assertTrue(token.transfer(ALICE, 25 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.balanceOf(ALICE), 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireBalance() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferOverBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_selfTransferOverBalanceStillReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(ALICE, 1);
    }

    function test_approveReplacesAndRevokesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 50 ether));
        assertEq(token.allowance(address(this), SPENDER), 50 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromSpendsAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 50 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 20 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), 30 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(ALICE), 20 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 30 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_transferFromInfiniteAllowanceIsNotDecremented() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferFromSelfStillSpendsAllowance() public {
        assertTrue(token.approve(SPENDER, 9));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 9));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_wrongSpenderCannotUseSomeoneElsesApproval() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromOverAllowanceRevertsWithoutChanges() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        token.transferFrom(address(this), ALICE, 11);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromOverBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroRollsBackAllowance() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromDoesNotNeedAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroSenderRevertsEvenForZeroAmount() public {
        // transferFrom checks the allowance owner before reaching the transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_distributionAndPoolStyleTransferPathsDeliverInFull() public {
        // These accounts model transfer legs only, not a live pool or distributor implementation.
        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 share = SUPPLY / 10;
        assertTrue(token.transfer(distributor, share));
        vm.prank(distributor);
        assertTrue(token.transfer(ALICE, share));
        assertEq(token.balanceOf(ALICE), share);
        assertEq(token.balanceOf(distributor), 0);
        assertTrue(token.transfer(pool, share));
        vm.prank(pool);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
        vm.prank(BOB);
        assertTrue(token.transfer(pool, 100 ether));
        assertEq(token.balanceOf(pool), share);
        assertEq(token.balanceOf(BOB), 0);
        assertTrue(token.transfer(BOB, SUPPLY - 2 * share));
        assertEq(token.balanceOf(BOB), SUPPLY - 2 * share);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_mintAndAdministrativeEntrypointsAreAbsent() public {
        assertTrue(token.transfer(ALICE, 100));
        bytes[12] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("issue(uint256)", 1),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("setMinter(address)", BOB),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("seize(address)", ALICE)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            assertTrue(!ok);
            vm.prank(BOB);
            (ok,) = address(token).call(calls[i]);
            assertTrue(!ok);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
            }
        }
    }

    function testFuzz_transfersConserveSupply(uint256 seed) public {
        uint256 amount = seed % (SUPPLY + 1);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_finiteAllowanceAccounting(uint256 approvalSeed, uint256 spendSeed) public {
        uint256 approved = approvalSeed % (SUPPLY + 1);
        uint256 spent = spendSeed % (approved + 1);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        assertEq(token.allowance(address(this), SPENDER), approved - spent);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientBalanceIsAtomic(uint256 seed) public {
        uint256 amount = SUPPLY + 1 + seed % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
