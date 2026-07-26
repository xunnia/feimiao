import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/assets/asset_media_store.dart';
import '../../widgets/app_toast.dart';

AssetMediaStore? _sharedStore;

/// 懒建并缓存全 App 共用的 [AssetMediaStore]（根=应用文档目录），
/// 消掉各弹层各自 `AssetMediaStore(applicationRoot: ...)` 的重复懒建。
Future<AssetMediaStore> sharedAssetMediaStore() async {
  return _sharedStore ??= AssetMediaStore(
    applicationRoot: await getApplicationDocumentsDirectory(),
  );
}

/// 统一的资产照片选择胶水：ImagePicker(quality 92) → 导入受管存储。
/// [previous] 非空时走 [AssetMediaStore.replaceFile]（先导入新图、成功后才删旧图）。
/// 用户取消或导入失败（失败已 toast 提示）返回 null。
Future<AssetMediaFiles?> pickAssetPhoto(
  BuildContext context,
  ImageSource source, {
  AssetMediaFiles? previous,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 92,
  );
  if (picked == null || !context.mounted) return null;
  try {
    final store = await sharedAssetMediaStore();
    return previous == null
        ? await store.importFile(picked.path)
        : await store.replaceFile(
            sourcePath: picked.path,
            previous: previous,
          );
  } on AssetMediaException catch (error) {
    if (context.mounted) showAppToast(context, error.message);
    return null;
  }
}
