import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';
import 'package:potato_notes/data/model/saved_image.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/controller.dart';
import 'package:potato_notes/internal/sync/image/queue_item.dart';

class DownloadQueueItem extends QueueItem {
  final String noteId;
  final String temporaryPath;

  DownloadQueueItem({
    required this.noteId,
    required this.temporaryPath,
    required String localPath,
    required SavedImage savedImage,
  }) : super(localPath: localPath, savedImage: savedImage);

  @action
  Future<void> downloadImage() async {
    status.value = QueueItemStatus.ongoing;
    await dio.download(
      Controller.files.url("get/${savedImage.hash}.jpg"),
      temporaryPath,
      onReceiveProgress: (count, total) {
        progress.value = count / total;
      },
      options: Options(
        headers: Controller.tokenHeaders,
      ),
    );
    await File(temporaryPath).rename(localPath);
    status.value = QueueItemStatus.complete;
  }
}
