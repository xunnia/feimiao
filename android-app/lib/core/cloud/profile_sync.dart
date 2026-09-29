import 'package:flutter/widgets.dart' show StringCharacters;

/// 昵称上限。服务端允许 1–20 字，App 两端统一只用 12 字（2026-09-29 用户定）。
/// 按"用户看到的字"算（emoji、带变音符的字都算 1 个），和输入框 `maxLength` 一致。
const int kNicknameMaxChars = 12;

/// 去掉首尾空白，超过 [kNicknameMaxChars] 个字就截断。
/// 本机输入和从服务端拉回来的昵称都走这里，所以别的客户端存了 20 字也只显示 12 字。
String normalizeNickname(String raw) {
  final trimmed = raw.trim();
  final chars = trimmed.characters;
  if (chars.length <= kNicknameMaxChars) return trimmed;
  return chars.take(kNicknameMaxChars).toString().trimRight();
}

enum NicknameSyncAction { none, push, pull }

/// 昵称该往哪边同步。规则见后端接口文档 §1「资料同步」：按 `updated_at` 取较新的。
///
/// - 两边（规范化后）一样：不动。
/// - 服务端没有：本机有就上传。
/// - 本机从没设置过（没有修改时间）：用服务端的。
/// - 都有：谁的修改时间新用谁；一样新时以服务端为准。
/// - 本机主动清空、而且比服务端新：不上传（服务端不接受空昵称），也不拉回旧名字。
NicknameSyncAction decideNicknameSync({
  required String local,
  required DateTime? localUpdatedAt,
  required String? remote,
  required DateTime? remoteUpdatedAt,
}) {
  final localName = normalizeNickname(local);
  final remoteName = normalizeNickname(remote ?? '');
  if (localName == remoteName) return NicknameSyncAction.none;
  if (remoteName.isEmpty) {
    return localName.isEmpty ? NicknameSyncAction.none : NicknameSyncAction.push;
  }
  if (localUpdatedAt == null) return NicknameSyncAction.pull;
  if (remoteUpdatedAt == null) {
    return localName.isEmpty ? NicknameSyncAction.none : NicknameSyncAction.push;
  }
  if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
    return localName.isEmpty ? NicknameSyncAction.none : NicknameSyncAction.push;
  }
  return NicknameSyncAction.pull;
}

/// 本机昵称存储。由记账仓库实现（通过适配器），账号模块不直接依赖账本。
abstract class LocalProfileStore {
  /// 本机资料是否已经从数据库读出来。没读完之前不能同步，否则会把空值当成"没设置"。
  bool get profileLoaded;

  /// 本机资料读完时完成。启动失败时可能永远不完成，调用方不要 await 在关键路径上。
  Future<void> whenProfileLoaded();

  String get nickname;

  /// 本机最后一次修改昵称的时间；从没改过（包括这个功能上线前设的昵称）为 null。
  DateTime? get nicknameUpdatedAt;

  /// 用服务端的昵称覆盖本机，修改时间记成服务端的时间。
  Future<void> applyCloudNickname(String nickname, DateTime? updatedAt);
}
