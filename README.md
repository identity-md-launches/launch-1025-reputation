# REPUTATION (REP)

A fixed supply ERC-20 implemented in `src/ReputationToken.sol:ReputationToken`.

| Parameter | Value |
| --- | --- |
| Name | REPUTATION |
| Symbol | REP |
| Decimals | 18 |
| Whole-token supply | 1,000,000,000 REP |
| Supply in base units | 1000000000000000000000000000 |
| Constructor arguments | None (`[]`) |
| Initial recipient | `msg.sender`, the immediate deploying address |

The constructor mints the entire supply once. A factory using CREATE or CREATE2 receives the
entire supply itself. There is no address to configure, owner, mint endpoint, burn endpoint,
pause, blacklist, tax, rebase, proxy, or upgrade mechanism. Transfers credit exactly their amount.
REP is transferable; its name does not introduce a reputation-scoring or nontransferability rule.

## Build and test

Install Foundry and Solidity **0.8.26** in the toolchain, then run:

```sh
forge build
forge test
forge fmt --check
```

The configuration pins Solidity 0.8.26, the Cancun EVM target, optimizer runs of 200, and
`bytecode_hash = "none"`. FFI and filesystem cheatcode permissions are disabled. Solidity dependencies
are vendored as ordinary files; builds need no package downloads when the pinned compiler is installed.
Tests use a small local cheatcode interface and neither read nor write environment variables.

The dependency is the unmodified ERC-20 subset of OpenZeppelin Contracts v5.0.2, commit
`dbb6104ce834628e473d2173bbc9d47f81a9eec3`. Its MIT license and per-file SHA-256 checksums are in
`lib/openzeppelin-contracts/`. The token adds only the fixed metadata and constructor mint.

Tests cover constructor events and factory deployment; exact transfers, self-transfers and zero
amounts; finite/infinite approvals and revocation; unauthorized spending, insufficient balances,
invalid addresses and atomic rollback; absent administrative endpoints; and prohibited runtime
opcodes. Fuzz tests exercise amount boundaries. Stateful invariants compare balances and allowances
against an independent model across randomized transfer/approval sequences (128 runs, depth 64).

## Deployment and assumptions

Use the creation bytecode from `out/ReputationToken.sol/ReputationToken.json`, with **no appended
constructor arguments**, or instantiate `new ReputationToken()` from the intended factory. Deploy
the concrete contract directly on a chain compatible with the configured EVM target. Do not put it
behind a proxy. The immediate deploying address must be capable of distributing its REP balance.

Before authorizing deployment, the operator should confirm the network, intended deployer/factory,
and compiled artifact. After deployment, verify the name, symbol, decimals, exact total supply,
constructor Transfer event, and initial deployer balance against the table above. Publish/verify the
source and compiler settings through the chosen chain's explorer.

The IdentityMD factory is responsible for the launch allocation, distributor, pool, and forwarding
the remainder. This token imposes no special exemptions or initialization steps on those transfers.
Launch economics, pool configuration, addresses, a launch manifest, and transaction broadcasting are
outside this token implementation. No requester-owned values are required to build this contract.

## After launch

There are no owner settings or maintenance calls. The holder of the initial balance is responsible
for distribution and safeguarding its signing authority. Each holder controls its own transfers and
allowances. Approvals replace the previous allowance; applications should account for the usual
allowance-change ordering risk (revoke and confirm before replacing a nonzero approval). A maximum
uint256 approval is unlimited and is not reduced by `transferFrom`; prefer limited allowances.

Zero-value transfers between nonzero addresses are supported. Sending to or approving the zero
address reverts. OpenZeppelin v5 emits Approval on `approve`, and Transfer on `transferFrom`; spending
an allowance does not emit another Approval event. Integrations should query `allowance` when needed.

There is no asset rescue mechanism. REP sent to this token contract, or assets sent to an address
unable to return them, cannot be recovered by an administrator. An ordinary native-currency send
to the token reverts because it has no payable receiver.

See `SECURITY.md` for the local review, analyzer results, and validation limitations. The supplied
platform integration harness requires platform contracts and launch parameters; local transfer-leg
tests are not a Uniswap v4 integration rehearsal or a production launch.
