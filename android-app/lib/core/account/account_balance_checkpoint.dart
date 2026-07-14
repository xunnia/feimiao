enum AccountBalanceQueryMode { current, historical }

enum AccountBalanceResolutionStatus { available, partial, unavailable }

enum AccountBalancePartialReason {
  unknownOpeningBalanceEffectiveTime,
  unknownSettlementDate,
  unknownSettlementAccount,
  missingReversalTarget,
}

class AccountBalanceQuery {
  final int accountId;
  final int asOfMs;
  final int asOfSequence;
  final int knowledgeCutoffMs;
  final AccountBalanceQueryMode mode;

  const AccountBalanceQuery({
    required this.accountId,
    required this.asOfMs,
    required this.knowledgeCutoffMs,
    required this.mode,
    this.asOfSequence = 0x7fffffff,
  });
}

class AccountOpeningBalance {
  final int amountMinor;
  final int? effectiveMs;
  final int sequence;

  const AccountOpeningBalance({
    required this.amountMinor,
    required this.effectiveMs,
    this.sequence = 0,
  });
}

/// An absolute balance anchor, or an immutable reversal record when
/// [reversalOf] is non-null.
class AccountBalanceCheckpoint {
  final String id;
  final int accountId;
  final int effectiveMs;
  final int sequence;
  final int knowledgeCutoffMs;
  final int targetBalanceMinor;
  final String? reversalOf;
  final Set<String> coveredUnknownEventIds;

  AccountBalanceCheckpoint({
    required this.id,
    required this.accountId,
    required this.effectiveMs,
    required this.sequence,
    required this.knowledgeCutoffMs,
    required this.targetBalanceMinor,
    this.reversalOf,
    Set<String> coveredUnknownEventIds = const {},
  }) : coveredUnknownEventIds = Set.unmodifiable(coveredUnknownEventIds);

  bool get isReversal => reversalOf != null;
}

/// One signed account leg. Transfers should be supplied as two legs.
class AccountBalanceMovement {
  final String id;
  final int? accountId;
  final Set<int> candidateAccountIds;
  final int deltaMinor;
  final int? settledMs;
  final int sequence;
  final int createdMs;

  AccountBalanceMovement({
    required this.id,
    required this.accountId,
    required this.deltaMinor,
    required this.settledMs,
    this.sequence = 0,
    this.createdMs = 0,
    Set<int> candidateAccountIds = const {},
  }) : candidateAccountIds = Set.unmodifiable(candidateAccountIds);

  bool mayAffect(int targetAccountId) =>
      accountId == targetAccountId ||
      (accountId == null &&
          (candidateAccountIds.isEmpty ||
              candidateAccountIds.contains(targetAccountId)));
}

class AccountBalanceCheckpointResult {
  final AccountBalanceResolutionStatus status;
  final int? balanceMinor;
  final String? anchorCheckpointId;
  final int? trustedFromMs;
  final Set<AccountBalancePartialReason> partialReasons;
  final List<String> includedMovementIds;
  final List<String> unresolvedMovementIds;

  AccountBalanceCheckpointResult({
    required this.status,
    required this.balanceMinor,
    required this.anchorCheckpointId,
    required this.trustedFromMs,
    required Set<AccountBalancePartialReason> partialReasons,
    required List<String> includedMovementIds,
    required List<String> unresolvedMovementIds,
  })  : partialReasons = Set.unmodifiable(partialReasons),
        includedMovementIds = List.unmodifiable(includedMovementIds),
        unresolvedMovementIds = List.unmodifiable(unresolvedMovementIds);
}

class AccountBalanceCheckpointResolver {
  static AccountBalanceCheckpointResult resolve({
    required AccountBalanceQuery query,
    required AccountOpeningBalance? openingBalance,
    required Iterable<AccountBalanceCheckpoint> checkpoints,
    required Iterable<AccountBalanceMovement> movements,
  }) {
    final allAccountCheckpoints = checkpoints
        .where((checkpoint) => checkpoint.accountId == query.accountId)
        .toList()
      ..sort(_compareCheckpoints);
    final visibleCheckpoints = allAccountCheckpoints
        .where((checkpoint) =>
            checkpoint.knowledgeCutoffMs <= query.knowledgeCutoffMs &&
            _atOrBeforeQuery(
              checkpoint.effectiveMs,
              checkpoint.sequence,
              query,
            ))
        .toList();

    final inactiveIds = <String>{};
    final activeAnchors = <AccountBalanceCheckpoint>[];
    final reasons = <AccountBalancePartialReason>{};
    final knownIds = allAccountCheckpoints.map((item) => item.id).toSet();

    // Reading backwards lets a reversal of a reversal restore the original
    // record without mutating old audit rows.
    for (final checkpoint in visibleCheckpoints.reversed) {
      if (inactiveIds.contains(checkpoint.id)) continue;
      final reversalOf = checkpoint.reversalOf;
      if (reversalOf != null) {
        inactiveIds.add(reversalOf);
        if (!knownIds.contains(reversalOf)) {
          reasons.add(AccountBalancePartialReason.missingReversalTarget);
        }
      } else {
        activeAnchors.add(checkpoint);
      }
    }
    activeAnchors.sort(_compareCheckpoints);
    final anchor = activeAnchors.isEmpty ? null : activeAnchors.last;

    if (anchor == null && openingBalance == null) {
      return AccountBalanceCheckpointResult(
        status: AccountBalanceResolutionStatus.unavailable,
        balanceMinor: null,
        anchorCheckpointId: null,
        trustedFromMs: null,
        partialReasons: reasons,
        includedMovementIds: const [],
        unresolvedMovementIds: const [],
      );
    }

    var balanceMinor =
        anchor?.targetBalanceMinor ?? openingBalance!.amountMinor;
    final startMs = anchor?.effectiveMs ?? openingBalance?.effectiveMs;
    final startSequence = anchor?.sequence ?? openingBalance?.sequence ?? 0;
    final startId = anchor?.id ?? '';
    if (anchor == null && openingBalance!.effectiveMs == null) {
      reasons.add(
        AccountBalancePartialReason.unknownOpeningBalanceEffectiveTime,
      );
    }

    final coveredUnknownIds = <String>{};
    if (anchor != null) {
      for (final checkpoint in activeAnchors) {
        if (_compareCheckpoints(checkpoint, anchor) > 0) break;
        coveredUnknownIds.addAll(checkpoint.coveredUnknownEventIds);
      }
    }

    final includedIds = <String>[];
    final unresolvedIds = <String>[];
    final orderedMovements = movements.toList()
      ..sort((left, right) => _compareMovementOrder(left, right));
    for (final movement in orderedMovements) {
      if (movement.createdMs > 0 &&
          movement.createdMs > query.knowledgeCutoffMs) {
        continue;
      }
      if (!movement.mayAffect(query.accountId)) continue;
      if (movement.accountId == null) {
        reasons.add(AccountBalancePartialReason.unknownSettlementAccount);
        unresolvedIds.add(movement.id);
        continue;
      }

      final settledMs = movement.settledMs;
      if (settledMs == null) {
        if (coveredUnknownIds.contains(movement.id)) continue;
        reasons.add(AccountBalancePartialReason.unknownSettlementDate);
        unresolvedIds.add(movement.id);
        if (query.mode == AccountBalanceQueryMode.current) {
          balanceMinor += movement.deltaMinor;
          includedIds.add(movement.id);
        }
        continue;
      }
      if (!_atOrBeforeQuery(settledMs, movement.sequence, query)) continue;
      if (startMs != null &&
          _compareOrder(
                settledMs,
                movement.sequence,
                movement.id,
                startMs,
                startSequence,
                startId,
              ) <=
              0) {
        continue;
      }
      balanceMinor += movement.deltaMinor;
      includedIds.add(movement.id);
    }

    return AccountBalanceCheckpointResult(
      status: reasons.isEmpty
          ? AccountBalanceResolutionStatus.available
          : AccountBalanceResolutionStatus.partial,
      balanceMinor: balanceMinor,
      anchorCheckpointId: anchor?.id,
      trustedFromMs: anchor?.effectiveMs ?? openingBalance?.effectiveMs,
      partialReasons: reasons,
      includedMovementIds: includedIds,
      unresolvedMovementIds: unresolvedIds,
    );
  }

  static bool _atOrBeforeQuery(
    int effectiveMs,
    int sequence,
    AccountBalanceQuery query,
  ) =>
      effectiveMs < query.asOfMs ||
      (effectiveMs == query.asOfMs && sequence <= query.asOfSequence);

  static int _compareCheckpoints(
    AccountBalanceCheckpoint left,
    AccountBalanceCheckpoint right,
  ) =>
      _compareOrder(
        left.effectiveMs,
        left.sequence,
        left.id,
        right.effectiveMs,
        right.sequence,
        right.id,
      );

  static int _compareMovementOrder(
    AccountBalanceMovement left,
    AccountBalanceMovement right,
  ) =>
      _compareOrder(
        left.settledMs ?? 0x7fffffffffffffff,
        left.sequence,
        left.id,
        right.settledMs ?? 0x7fffffffffffffff,
        right.sequence,
        right.id,
      );

  static int _compareOrder(
    int leftMs,
    int leftSequence,
    String leftId,
    int rightMs,
    int rightSequence,
    String rightId,
  ) {
    final ms = leftMs.compareTo(rightMs);
    if (ms != 0) return ms;
    final sequence = leftSequence.compareTo(rightSequence);
    if (sequence != 0) return sequence;
    return leftId.compareTo(rightId);
  }
}
