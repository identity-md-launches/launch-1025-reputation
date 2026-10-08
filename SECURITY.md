# Local security and validation record

## Scope of this change

The existing one-time mint of 10^27 base units and ERC-20 allowance implementation are preserved.
`src/ReputationToken.sol` now adds a default 50-basis-point transfer burn, an owner-only fee setter,
owner-only pause/unpause, and two-step ownership handover. The deployer is the initial owner.
The existing vendored OpenZeppelin ERC-20, compiler configuration, and dependencies are unchanged.

The pinned security reference was used as review data for access control, integer arithmetic,
fee-on-transfer accounting, input validation, events, and administrative trust. No token operation
calls an external contract or recipient callback; there is no reentrancy interaction, oracle,
randomness, signature, delegatecall, proxy, or upgrade path to secure in this implementation.

| State-changing entry point | Authority | State/effect | Coverage |
| --- | --- | --- | --- |
| Constructor | Immediate deployer | Mint once, establish owner; mint is untaxed | Metadata, supply, events, CREATE2/factory tests |
| `transfer` | Holder | Debit gross amount, credit net, reduce supply by fee | Events, rounding, full/zero/self transfers, failures, fuzz and model |
| `transferFrom` | Approved spender | Same burn; consume gross finite allowance | Finite/infinite approvals, wrong spender, rollback, fuzz and model |
| `approve` | Allowance owner | Set/replace/revoke even while paused | Invalid addresses, isolation, boundaries and model |
| `setFeeBps` | Current owner | Set rate in [0, 10,000], emit change | Both endpoints, invalid bounds, unauthorized callers, fuzz and model |
| `pause` / `unpause` | Current owner | Stop/resume all transfers | Repeated transitions, unauthorized callers, rollback, model |
| `transferOwnership` | Current owner | Nominate/replace pending owner | Invalid nominees, unauthorized caller, replaced nominee |
| `acceptOwnership` | Pending owner | Complete handover, clear pending owner | Wrong/replayed acceptance, former owner loses powers, paused recovery |

## Accounting and failure analysis

The overridden `_update` hook covers both inherited transfer methods. The constructor mint bypasses
fee calculation. The hook first checks pause state and the sender's **gross** balance, then computes
and burns the fee using the base ERC-20 update, and credits the net amount using the same base
implementation. Calling the base implementation avoids recursively taxing the burn itself.

Checking gross balance before multiplication both preserves self-transfer semantics and bounds
`amount * feeBps` by 10^31, well below uint256 capacity. This argument relies on the concrete
contract's sole constructor mint and the fee setter's 10,000 bound. Even uint256-maximum transfer
requests fail with the balance error rather than an arithmetic panic. Fee rounding is downward
per transfer, without accumulated dust. Zero-burn events are omitted; the net Transfer event is
always emitted, even for zero amounts or a 100% fee.

The independent stateful model checks `sum(balances) == totalSupply()` and
`totalSupply() + cumulativeBurns == INITIAL_SUPPLY`, plus each balance and allowance. It mixes
fee changes, pauses, transfers, self-transfers, round trips, approvals, and expected failures.
Expected reverts leave the model unchanged; unexpected reverts fail the campaign. Standard zero
address guards remain inherited. An insufficient allowance may revert before the pause check;
a later transfer failure rolls back earlier allowance consumption atomically.

No external mint, discretionary burn, seizure, or upgrade endpoint is added. Runtime scanning
checks for forbidden delegatecall, callcode, and selfdestruct opcodes alongside absent-selector
tests. This is supporting evidence, not an exhaustive bytecode proof or independent audit.

## Validation for this revision

Local tools: Forge 1.8.3 (`cae51ad458f6abb64852b7709eb784352429825d`) and the pinned Solidity
0.8.26. Required commands:

```sh
forge build
forge test
forge fmt --check
```

The full test run passed **67 reported entries**, zero failures and zero skips. This Forge version
groups the four stateful invariant predicates into one reported entry; they ran 256 sequences
of depth 64 (16,384 calls), with zero handler reverts. The other 66 entries include 11 fuzz tests
at 1,000 cases each. Tests neither read nor modify environment variables and do not require a
network, an RPC, or a caller-dependent deployment script.

`forge build` passed with Solidity 0.8.26. `forge fmt --check` passed after formatting, and
`git diff --check` passed. Only the token source, tests, README, and this record changed;
protected configuration and dependency files are unchanged. The older project's Slither
results concern its prior fee-free source and do not validate this revision. Slither,
Mythril, live-chain/fork tests, explorer verification, and an independent adversarial audit have
not been run for this change.

## Trust assumptions and operational responsibilities

The owner can set any fee from 0% to 100% immediately and can pause transfers indefinitely.
The initial 0.5% is therefore a default rather than an immutable rate. A 100% rate destroys the
entire amount of each successful transfer; it is tested and explicitly documented. Approvals
and ownership/fee administration remain available while paused. There is no renunciation method,
but loss of the owner's signing capability can still permanently lock a paused token. Review
owner custody and the two-step handover, particularly when a factory is the immediate deployer.

There are no address exemptions. All launch distribution and pool transfer legs receive net
amounts after fees, so previous exact-transfer integration assumptions no longer apply. The
platform must review and test its actual launch/distributor/pool code with this behavior; local
address-based transfer fixtures are not a real integration rehearsal. Existing on-chain code
is unaffected and has no upgrade path in this deliverable.

No transactions were broadcast, no token was redeployed or re-minted on chain, and no keys were
accessed. Before production use, the network remains responsible for independent adversarial
review, integration validation, owner handover verification, and explorer/source verification.
Passing local tests does not replace that review.
