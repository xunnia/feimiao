import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/account/account_balance_checkpoint.dart';

const _opening = AccountOpeningBalance(
  amountMinor: 10000,
  effectiveMs: 100,
);

AccountBalanceQuery _query({
  AccountBalanceQueryMode mode = AccountBalanceQueryMode.current,
  int asOfMs = 1000,
}) =>
    AccountBalanceQuery(
      accountId: 1,
      asOfMs: asOfMs,
      knowledgeCutoffMs: 2000,
      mode: mode,
    );

AccountBalanceCheckpoint _anchor({
  required String id,
  required int effectiveMs,
  required int target,
  int sequence = 0,
  String? reversalOf,
  Set<String> covered = const {},
}) =>
    AccountBalanceCheckpoint(
      id: id,
      accountId: 1,
      effectiveMs: effectiveMs,
      sequence: sequence,
      knowledgeCutoffMs: effectiveMs,
      targetBalanceMinor: target,
      reversalOf: reversalOf,
      coveredUnknownEventIds: covered,
    );

AccountBalanceMovement _movement({
  required String id,
  required int delta,
  int? settledMs,
  int? accountId = 1,
  int sequence = 0,
  int createdMs = 0,
}) =>
    AccountBalanceMovement(
      id: id,
      accountId: accountId,
      deltaMinor: delta,
      settledMs: settledMs,
      sequence: sequence,
      createdMs: createdMs,
    );

void main() {
  test('absolute anchor ignores a later backfilled pre-anchor movement', () {
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(),
      openingBalance: _opening,
      checkpoints: [_anchor(id: 'anchor', effectiveMs: 500, target: 50000)],
      movements: [
        _movement(
            id: 'backfilled', delta: 9000, settledMs: 400, createdMs: 900),
        _movement(id: 'after', delta: -2000, settledMs: 600),
      ],
    );

    expect(result.status, AccountBalanceResolutionStatus.available);
    expect(result.balanceMinor, 48000);
    expect(result.includedMovementIds, ['after']);
  });

  test('reversing the latest anchor falls back to the previous anchor', () {
    final first = _anchor(id: 'a', effectiveMs: 300, target: 30000);
    final second = _anchor(id: 'b', effectiveMs: 500, target: 50000);
    final reversal = _anchor(
      id: 'revoke-b',
      effectiveMs: 700,
      target: 0,
      reversalOf: 'b',
    );
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(),
      openingBalance: _opening,
      checkpoints: [first, second, reversal],
      movements: [
        _movement(id: 'between', delta: 4000, settledMs: 400),
        _movement(id: 'after', delta: -1000, settledMs: 600),
      ],
    );

    expect(result.anchorCheckpointId, 'a');
    expect(result.balanceMinor, 33000);
  });

  test('reversing a reversal restores the target anchor', () {
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(),
      openingBalance: _opening,
      checkpoints: [
        _anchor(id: 'a', effectiveMs: 300, target: 30000),
        _anchor(id: 'b', effectiveMs: 500, target: 50000),
        _anchor(id: 'r1', effectiveMs: 600, target: 0, reversalOf: 'b'),
        _anchor(id: 'r2', effectiveMs: 700, target: 0, reversalOf: 'r1'),
      ],
      movements: const [],
    );

    expect(result.anchorCheckpointId, 'b');
    expect(result.balanceMinor, 50000);
  });

  test('same instant uses sequence and id for deterministic ordering', () {
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(),
      openingBalance: _opening,
      checkpoints: [
        _anchor(
            id: 'm-checkpoint', effectiveMs: 500, sequence: 10, target: 20000),
      ],
      movements: [
        _movement(id: 'before', delta: 1000, settledMs: 500, sequence: 9),
        _movement(id: 'z-after', delta: 3000, settledMs: 500, sequence: 10),
        _movement(id: 'n-after', delta: 2000, settledMs: 500, sequence: 10),
      ],
    );

    expect(result.balanceMinor, 25000);
    expect(result.includedMovementIds, ['n-after', 'z-after']);
  });

  test('covered unknown event is absorbed and not added twice', () {
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(),
      openingBalance: _opening,
      checkpoints: [
        _anchor(
          id: 'anchor',
          effectiveMs: 500,
          target: 50000,
          covered: {'legacy-refund'},
        ),
      ],
      movements: [
        _movement(id: 'legacy-refund', delta: 8000),
      ],
    );

    expect(result.status, AccountBalanceResolutionStatus.available);
    expect(result.balanceMinor, 50000);
    expect(result.unresolvedMovementIds, isEmpty);
  });

  test('a new unknown event remains partial for current balance', () {
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(),
      openingBalance: _opening,
      checkpoints: [
        _anchor(
          id: 'anchor',
          effectiveMs: 500,
          target: 50000,
          covered: {'old'},
        ),
      ],
      movements: [
        _movement(id: 'new', delta: -1500, createdMs: 700),
      ],
    );

    expect(result.status, AccountBalanceResolutionStatus.partial);
    expect(result.balanceMinor, 48500);
    expect(
      result.partialReasons,
      contains(AccountBalancePartialReason.unknownSettlementDate),
    );
    expect(result.unresolvedMovementIds, ['new']);
  });

  test('historical balance never guesses an unknown settlement date', () {
    final result = AccountBalanceCheckpointResolver.resolve(
      query: _query(mode: AccountBalanceQueryMode.historical),
      openingBalance: _opening,
      checkpoints: [_anchor(id: 'anchor', effectiveMs: 500, target: 50000)],
      movements: [_movement(id: 'unknown', delta: -1500)],
    );

    expect(result.status, AccountBalanceResolutionStatus.partial);
    expect(result.balanceMinor, 50000);
    expect(result.includedMovementIds, isEmpty);
  });
}
