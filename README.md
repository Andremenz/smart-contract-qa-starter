# Smart Contract QA Portfolio — Staking Rewards

A Foundry-based QA portfolio project built around an educational Solidity staking/rewards contract. It demonstrates test design, adversarial token simulation, regression testing, fuzzing, and static-analysis triage.

**Scope:** this is an educational test target, not an audited protocol, formal verification result, or production-ready financial application.

## What the project demonstrates

- Reading and testing Solidity contract behavior.
- Unit and regression tests for staking, withdrawal, rewards, access control, and invalid inputs.
- Bounded fuzz testing of stake/withdraw accounting.
- Time-based reward accrual and reward-reserve accounting.
- Adversarial ERC-20 behavior: false returns, reverts, malformed return values, fee-on-transfer behavior, and callbacks.
- Reentrancy-guard checks across state-changing entry points.
- A read-only callback regression test for transient accounting/custody consistency.
- Static-analysis execution and manual triage of findings.

## Stack

- Solidity 0.8.24
- Foundry / Forge
- forge-std
- Slither (optional static-analysis tool)

## Setup (Ubuntu / WSL)

Install Foundry using the official instructions: https://getfoundry.sh/

From the repository root:

```bash
git submodule update --init --recursive
forge build
forge test -vv
forge test --gas-report
forge fmt --check
```

Run static analysis if Slither is installed:

```bash
slither .
```

## Test coverage

### Standard tests

The standard suite covers:

- Stake and withdrawal accounting.
- Reward accrual and claims.
- Fuzzed stake/withdraw amounts.
- Zero-value and over-withdrawal reverts.
- Owner-only reward notification.
- Active reward-period protection.
- Duplicate-claim prevention.
- Prevention of reusing funds reserved for unclaimed rewards.
- Frequent reward checkpoints and conservative reserve accounting.
- Multiple stakers and partial withdrawals.

### Adversarial tests

The adversarial suite covers:

- EOA and zero-address token rejection.
- Identical staking/reward token rejection.
- False-returning and reverting `transferFrom`.
- Fee-on-transfer staking-token rejection.
- False-returning withdrawal and reward transfers.
- Malformed ERC-20 return data.
- Callback attempts to reenter `stake`, `withdraw`, `getReward`, and `notifyRewardAmount`.
- Read-only callback observation of staking-token custody and staking accounting.

Run the adversarial suite alone:

```bash
forge test --match-contract StakingRewardsAdversarialTest -vv
```

## Design notes and limitations

- The staking contract intentionally accepts only exact-transfer, non-rebasing staking-token behavior. Fee-on-transfer deposits are rejected.
- `stake` applies checks-effects-interactions: accounting is updated before `transferFrom`, and a failed or inexact transfer reverts the whole transaction.
- The reentrancy lock protects state-changing entry points. The callback tests exercise each of those entry points.
- The read-only callback test demonstrates consistency for the mock token's post-transfer callback ordering. It does **not** prove that arbitrary malicious token callbacks or every external integration are safe.
- `totalOutstandingRewards` conservatively reserves scheduled emissions while stake is present. Per-user reward-per-token rounding can leave residual reserve dust. This implementation does not provide a dust-recovery mechanism; residual reserve may remain locked and must be considered in any redesign.
- Reward calculations use integer arithmetic. Extremely large values may revert on checked-arithmetic overflow; production designs need explicit bounds and economic review.
- The constructor checks that token addresses are nonzero contracts, but it does not prove that a token is honest or economically safe.
- The low-level token-call helper accepts either empty return data or a 32-byte-or-longer return whose first ABI word is `true`. This is an intentional compatibility choice, not proof of full ERC-20 compliance.
- Slither findings require manual assessment. Timestamp comparisons, low-level calls, assembly, and empty-return handling may be intentional in this example; do not suppress findings without documenting why.

## Static-analysis reporting

Record the exact Slither version, command, date, detector names, affected functions, manual assessment, and any unresolved concerns when publishing results. Do not describe a detector warning as an exploitable vulnerability unless a reproducible impact has been established.

## Honest portfolio description

"Built a Foundry-based QA suite for an educational Solidity staking/rewards contract, covering core accounting, time-based rewards, access control, bounded fuzz testing, adversarial ERC-20 behavior, callback/reentrancy regression tests, and static-analysis triage."

Only publish test counts, coverage percentages, or static-analysis conclusions after running the commands locally and reviewing their actual output. Do not describe this educational exercise as a production audit or claim professional smart-contract audit experience.
