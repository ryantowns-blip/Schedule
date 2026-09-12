import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

class ScreenshotCleanupResult {
  const ScreenshotCleanupResult({
    required this.requested,
    required this.matched,
    required this.deleted,
    required this.permissionDenied,
  });

  final int requested;
  final int matched;
  final int deleted;
  final bool permissionDenied;

  int get unmatched => requested - matched;
  int get failedDeletion => matched - deleted;
}

class ScreenshotCleanupService {
  const ScreenshotCleanupService();

  Future<ScreenshotCleanupResult> deleteSourceImages(List<XFile> images) async {
    if (images.isEmpty) {
      return const ScreenshotCleanupResult(
        requested: 0,
        matched: 0,
        deleted: 0,
        permissionDenied: false,
      );
    }

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      return ScreenshotCleanupResult(
        requested: images.length,
        matched: 0,
        deleted: 0,
        permissionDenied: true,
      );
    }

    final targets = <_ScreenshotTarget>[];
    for (final image in images) {
      try {
        targets.add(_ScreenshotTarget(
          name: image.name.trim().toLowerCase(),
          size: await image.length(),
        ));
      } catch (_) {
        // Without both filename and size we cannot safely identify the source
        // media asset, so leave that screenshot untouched.
      }
    }

    final targetKeys = targets.map((target) => target.key).toSet();
    final candidates = <String, List<String>>{};
    const pageSize = 200;
    final count = await PhotoManager.getAssetCount(type: RequestType.image);

    for (var page = 0; page * pageSize < count; page++) {
      final assets = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: pageSize,
        type: RequestType.image,
      );
      if (assets.isEmpty) break;

      for (final asset in assets) {
        final name = (await asset.titleAsync).trim().toLowerCase();
        if (name.isEmpty) continue;

        final possibleKeys = targetKeys.where((key) => key.startsWith('$name|'));
        if (possibleKeys.isEmpty) continue;

        final size = await asset.fileSize;
        final key = '$name|$size';
        if (!targetKeys.contains(key)) continue;
        candidates.putIfAbsent(key, () => <String>[]).add(asset.id);
      }
    }

    // Only delete when the device library has exactly one asset matching the
    // selected screenshot's filename and byte size. Ambiguous matches are left
    // alone to avoid deleting the wrong photo.
    final idsToDelete = <String>[];
    var matched = 0;
    for (final target in targets) {
      final ids = candidates[target.key] ?? const <String>[];
      if (ids.length != 1) continue;
      matched++;
      idsToDelete.add(ids.single);
    }

    final uniqueIds = idsToDelete.toSet().toList();
    final deletedIds = uniqueIds.isEmpty
        ? const <String>[]
        : await PhotoManager.editor.deleteWithIds(uniqueIds);

    return ScreenshotCleanupResult(
      requested: images.length,
      matched: matched,
      deleted: deletedIds.length,
      permissionDenied: false,
    );
  }
}

class _ScreenshotTarget {
  const _ScreenshotTarget({required this.name, required this.size});

  final String name;
  final int size;

  String get key => '$name|$size';
}
