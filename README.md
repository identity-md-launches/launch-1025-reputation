# REPUTATION (REP)

`src/ReputationToken.sol:ReputationToken` mints its supply once and burns **0.5% of each transfer
by default**. Only the owner can change the burn fee, pause, or unpause transfers.

| Parameter | Value |
| --- | --- |
| Name / symbol | REPUTATION / REP |
| Decimals | 18 |
| Initial whole-token supply | 1,000,000,000 REP |
| Initial supply in base units | 1000000000000000000000000000 |
| Constructor arguments | None (`[]`) |
| Initial recipient and owner | `msg.sender`, the immediate deploying address |
| Initial burn fee | 50 basis points (0.5%) |
| Allowed burn fee | 0–10,000 basis points (0–100%), inclusive |
| Initial pause state | Unpaused |

The constructor mints the entire initial supply without a fee. Supply then decreases with burns;
there is no subsequent mint, public discretionary burn, blacklist, seizure, asset rescue, rebase,
proxy, or upgrade mechanism. REP remains transferable and has no reputation-scoring rules.

## Transfer behavior and assumptions

The requested 0.5% is the **initial** rate because the brief also permits the owner to set the fee.
The brief specifies no narrower fee limit, so the setter accepts any whole basis-point rate from
0% through 100%. This is a significant owner power: 0 disables the burn, and 10,000 burns the
entire amount of subsequent transfers, delivering zero to the recipient. There is no timelock.

For a requested gross amount `amount`, in 18-decimal base units:

```text
burned   = floor(amount * feeBps / 10_000)
received = amount - burned
```

The sender spends `amount`, the recipient receives `received`, and `totalSupply()` decreases by
`burned`. The fee is deducted from the amount, not charged on top or sent to an owner/treasury.
At the default rate a 100 REP transfer delivers 99.5 REP and destroys 0.5 REP. The burn emits
`Transfer(sender, address(0), burned)` when nonzero, followed by
`Transfer(sender, recipient, received)`. The zero address never holds the burned tokens.

Both `transfer` and `transferFrom` apply the same fee. `transferFrom` requires and consumes the
**gross** allowance; unlimited (`uint256.max`) allowances remain unchanged. A self-transfer also
burns the fee, reduces the sender's balance only by that fee, and still requires the full gross
balance and, for delegated transfers, the full gross allowance. All failure paths roll back the
burn, balances, and allowance together. The owner has no transfer or allowance bypass.

Fees round down independently per transfer. At the default rate, amounts below 200 base units
burn zero; 200 base units burn one. Splitting transfers can reduce rounding fees; fractional
remainders are not carried forward. Zero-amount transfers between nonzero addresses emit a
zero-value Transfer while unpaused. Transfers to the zero address and zero-address approvals
revert, as in the existing ERC-20 implementation.

There are no exempt addresses or transaction types: owner distributions, factory allocations,
distributor claims, pool movements, and transfers to the token contract all incur the active fee.
Integrations must account for actual received balances and repeated fees on successive legs.
Existing integrations that assume exact transfer amounts require review; the local pool-style
transfer tests do not demonstrate compatibility with a deployed pool, router, or launch factory.

## Owner controls

| Function | Authorized caller | Effect |
| --- | --- | --- |
| `setFeeBps(uint256)` | Current owner | Set a rate from 0 to 10,000; emit `FeeUpdated(old, new)` |
| `pause()` | Current owner | Stop transfers; emit `Paused(caller)` |
| `unpause()` | Current owner | Resume transfers; emit `Unpaused(caller)` |
| `transferOwnership(address)` | Current owner | Nominate a nonzero owner other than the token itself; emit `OwnershipTransferStarted` |
| `acceptOwnership()` | Pending owner | Complete handover, clear nomination; emit `OwnershipTransferred` |

Pausing blocks both transfer methods, including self-transfers, zero amounts, and owner transfers.
Approvals, approval revocation, fee changes, and ownership handover remain available while paused.
Repeated pause/unpause calls in the same state revert. Invalid-address and allowance validation
can occur before the pause check; every attempted paused transfer still reverts atomically.

The current owner retains all rights until the nominee accepts; the previous owner loses all
rights upon acceptance. A new nomination replaces an old one. To cancel a nomination, the owner
can nominate itself and accept. Ownership does not move token balances. There is no renunciation
endpoint, avoiding deliberate abandonment of the unpause authority. Losing access to the owner
can still permanently prevent unpausing or changing the fee.

## Build and test

With Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

The unchanged configuration pins Solidity 0.8.26, Cancun, optimizer runs of 200, and
`bytecode_hash = "none"`. FFI and filesystem cheatcode permissions are disabled. The existing
OpenZeppelin Contracts v5.0.2 ERC-20 subset is vendored as ordinary files under
`lib/openzeppelin-contracts/` (commit `dbb6104ce834628e473d2173bbc9d47f81a9eec3`), with its license
and checksums. No dependency or build-configuration changes are needed. The owner and pause
controls are implemented locally in ReputationToken; no additional dependency was installed.

Tests use the existing local cheatcode interface, no environment variables, network, keys, or
forks. Coverage includes untaxed minting, factory ownership, burn events and rounding, both
transfer methods, self/zero/full transfers, finite/infinite allowances, atomic failures,
owner-only fee/pause controls, rate limits, and ownership handover. Eleven fuzz tests each run
1,000 cases. Four stateful predicates compare balances, cumulative burns, allowances, metadata,
and administration against an independent model over 256 runs of depth 64.

## Deployment parameters and project continuity

This assignment delivers source changes only. No deployment, redeployment, replacement, re-mint,
or on-chain transaction is performed. Editing this non-upgradeable contract cannot change any
existing deployed bytecode. No migration or upgrade path is introduced.

The artifact remains `out/ReputationToken.sol/ReputationToken.json`, with no constructor
arguments. Its constructor behavior is documented above for review and local reproduction.
The immediate deployer owns the contract and receives the whole initial supply; a CREATE/CREATE2
factory receives both, rather than the transaction origin. That factory must be able to
nominate the intended operational owner and distribute its balance. The intended owner must
then call `acceptOwnership()`; a factory without an administrative forwarding/handover path
would retain inaccessible control. No requester address has been guessed or embedded.

The deployment operator is responsible for checking chain/EVM compatibility, the artifact,
owner custody, factory handover support, initial metadata/supply/fee/pause state, constructor
events, and source verification. Launch allocations, distributor/pool compatibility and
configuration, and the launch manifest remain the platform's responsibility. The project
history's unresolved pool parameters are outside this source change.

## After launch

The owner should monitor `FeeUpdated`, `Paused`, `Unpaused`, and ownership events and maintain
an operational signer able to call `unpause()`. Keep `feeBps()` at 50 for the requested 0.5% fee;
use `setFeeBps(newRate)` only for an intentional policy change communicated to holders and
integrations. No external service, oracle, treasury address, or other configuration is required.

Holders trust the owner to choose fees and determine when transfers are available. A compromised
owner can freeze all holders or burn up to 100% of future transfer amounts, but cannot mint or
spend balances without their allowances. Ownership can be handed to an operational multisig
through the two-step process. Fee changes apply at execution, including to pending transactions;
applications must account for changing net receipts.

Holders remain responsible for their keys and allowances. Prefer bounded approvals; revoke and
confirm before replacing a nonzero allowance when transaction ordering matters. Approval spending
does not emit another Approval event in the vendored ERC-20; query `allowance` as needed.
Assets sent to the token contract cannot be rescued. Plain native-currency sends revert.

See `SECURITY.md` for this change's validation record and remaining review responsibilities.
