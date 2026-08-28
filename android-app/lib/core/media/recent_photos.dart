import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:photo_manager/photo_manager.dart';

/// A recent gallery item used by the Claude-style attachment rail.
///
/// The widget only receives a thumbnail and a lazy path resolver, so the UI
/// never keeps full-size gallery files in memory.
class ChatRecentPhoto {
  final String id;
  final Uint8List thumbnail;
  final Future<String?> Function() loadPath;

  const ChatRecentPhoto({
    required this.id,
    required this.thumbnail,
    required this.loadPath,
  });
}

abstract final class RecentPhotoStore {
  static Future<List<ChatRecentPhoto>> load({int limit = 12}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return const [];
    }

    try {
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.image,
            mediaLocation: false,
          ),
        ),
      );
      if (!permission.isAuth && permission != PermissionState.limited) {
        return const [];
      }

      final recentFirst = FilterOptionGroup(
        orders: const [OrderOption(type: OrderOptionType.createDate)],
      );
      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
        filterOption: recentFirst,
      );
      if (paths.isEmpty) return const [];

      final assets = await paths.first.getAssetListPaged(
        page: 0,
        size: limit,
        type: RequestType.image,
      );
      final result = <ChatRecentPhoto>[];
      for (final asset in assets) {
        final thumbnail = await asset.thumbnailDataWithSize(
          const ThumbnailSize.square(240),
          quality: 86,
        );
        if (thumbnail == null || thumbnail.isEmpty) continue;
        result.add(
          ChatRecentPhoto(
            id: asset.id,
            thumbnail: thumbnail,
            loadPath: () async => (await asset.loadFile(isOrigin: false))?.path,
          ),
        );
      }
      return List.unmodifiable(result);
    } catch (_) {
      // Permission denial, an unavailable media provider, and old Android
      // gallery implementations should all fall back to the Photos button.
      return const [];
    }
  }
}
