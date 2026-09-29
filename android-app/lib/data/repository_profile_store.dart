import '../core/cloud/profile_sync.dart';
import 'app_repository.dart';

/// 把记账仓库里的本机昵称交给账号模块同步。只转发昵称，不碰账本。
class RepositoryProfileStore implements LocalProfileStore {
  RepositoryProfileStore(this._repo);

  final AppRepository _repo;

  @override
  bool get profileLoaded => _repo.profileLoaded;

  @override
  Future<void> whenProfileLoaded() => _repo.profileLoadedFuture;

  @override
  String get nickname => _repo.profileNickname;

  @override
  DateTime? get nicknameUpdatedAt => _repo.profileNicknameUpdatedAt;

  @override
  Future<void> applyCloudNickname(String nickname, DateTime? updatedAt) =>
      _repo.applyCloudNickname(nickname, updatedAt);
}
