# Local security and validation record

## Scope and invariants

Reviewed `src/ReputationToken.sol` and its vendored OpenZeppelin ERC-20 implementation. The
constructor is the only path to `_mint`; it mints exactly 10^27 base units to `msg.sender`.
No external/public mint, burn, administrator, initialization, or upgrade function exists in the
built ABI. No token operation makes an external call or invokes a recipient callback.

| State-changing entry point | Authority | State/effect | Verification |
| --- | --- | --- | --- |
| Constructor | Immediate deployer | Mint the full supply to that deployer; emit Transfer from zero | Metadata/supply, event, and CREATE2 factory tests |
| `transfer` | Holder | Debit caller, credit nonzero recipient exactly; preserve supply | Success, self/zero/full transfers, balance failures, fuzz, stateful model |
| `approve` | Allowance owner | Replace caller's allowance for a nonzero spender; emit Approval | Set/replace/revoke, zero spender, stateful allowance model |
| `transferFrom` | Approved spender | Debit owner and credit recipient; consume finite allowance | Finite/infinite allowance, wrong spender, insufficient balance/allowance, rollback, stateful model |

Both balance conservation and allowance accounting are checked after randomized sequences against
an independent model of four actors. Invalid operations must revert without altering balances,
allowances, or supply. ABI inspection and bytecode scanning complement tests of common unauthorized
mint/administrative selectors; testing a finite selector list alone is not proof of their absence.

## Commands and observed results

Validation used Forge 1.8.3 (`cae51ad458f6abb64852b7709eb784352429825d`), Solidity
`0.8.26+commit.8a97fa7a`, and Slither **0.11.6**. The commands were run from the project root with:

```sh
export PATH=/home/worker/.local/share/imd-tools/slither/bin:/home/worker/.foundry/bin:$PATH
forge build
forge test
forge fmt --check
slither .
```

- `forge build`: passed with the pinned compiler.
- `forge test`: passed, 30 reported test entries, zero failures/skips. This Forge version groups
  the two invariant predicates into one entry; the other 29 entries include three fuzz tests at
  1,000 runs each. Invariants completed 128 runs of depth 64 (8,192 calls), zero handler reverts.
- `forge fmt --check`: passed after `forge fmt`.
- A fresh copy containing only the delivered sources, tests, vendored dependencies, configuration,
  and documentation also passed `forge build --offline`, `forge test --offline --threads 4`, and
  `forge fmt --check`, with only PATH present in the process environment. The copy contained no
  protected inputs or preexisting build cache.
- `slither .`: analyzed eight contracts/interfaces using 102 detectors; returned exit 255 with
  the two findings below. This was a completed analysis with findings, not a clean scan.
- Local artifact validation checked TOML/JSON parsing, all vendored SHA-256 checksums, compiler
  metadata, an empty constructor argument list, the exact ABI function set, and runtime size
  (1,752 bytes). No ABI mint/administrative functions or unexpected constructor settings appeared.

An initial zero-source `transferFrom` test expected `ERC20InvalidSender`, but the implementation
first rejects that address as the allowance owner with `ERC20InvalidApprover`. The assertion was
corrected after inspecting `_spendAllowance` and `_approve`; the focused test and full suite passed.
The contract was not changed to accommodate the test.

## Slither finding disposition

1. **`pragma` — different Solidity version constraints.** The unmodified library uses `^0.8.20`;
   the project uses `0.8.26`. Both are compiled together with exactly 0.8.26, as confirmed in the
   artifact. This is a source-policy warning, not evidence of mixed compiler versions or an
   exploitable defect in this build. The library's original source and provenance were preserved.
2. **`solc-version` — the library's range permits older affected compilers.** Slither lists
   `VerbatimInvalidDeduplication`, `FullInlinerNonExpressionSplitArgumentEvaluationOrder`, and
   `MissingSideEffectsOnSelectorAccess` against `^0.8.20`. The project does not select the lower
   bound of that range; it pins 0.8.26. Production sources contain no inline assembly/verbatim,
   custom Yul optimizer configuration, or selector-access expressions with side effects. No
   triggering path or token vulnerability was demonstrated. Keep the pinned compiler/settings
   when reproducing these results; they do not validate every compiler allowed by the library pragma.

No confirmed vulnerabilities were identified in this local review. Neither finding was suppressed,
and no vendor pragma or detector configuration was changed to force a successful analyzer exit.

## Remaining limitations and operational responsibilities

The supplied protected harness was read but not executed: it imports platform-only
`LaunchLiquidity.sol`, `PoolInitializationGuard.sol`, `HookFlags.sol`, Uniswap v4, and forge-std,
and requires the actual launch's `IMD_*` values. These are not in the input project. Local tests
exercise exact distribution and pool-style token transfers, not pool initialization, liquidity
seeding, swaps, the Merkle distributor implementation, or the network's manifest resolution.
The platform must execute its integration harness with its own contracts and real launch inputs.

There are no administrative recovery or transfer-freezing powers. The initial holder controls all
tokens until distribution; holders bear allowance and key-custody risk. See README for deployment
checks and ERC-20 allowance semantics. No transactions were broadcast and no wallet keys accessed.
Mythril, fork/live-chain tests, explorer verification, and an independent adversarial audit were
not performed. Passing tests and this static review do not prove security; production release
still needs the network's independent review and deployment checks.
