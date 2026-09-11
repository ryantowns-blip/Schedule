import 'dart:io';

import 'package:pdfx/pdfx.dart';

/// Renders a local PDF to temporary PNG files for the existing screenshot OCR
/// pipeline. WMT Print/Save-as-PDF output can therefore use the same review and
/// parsing safeguards as screenshots even when the PDF does not expose a text
/// layer through the app.
class PdfScheduleImportService {
  const PdfScheduleImportService();

  Future<List<String>> renderToTemporaryImages(String pdfPath) async {
    final document = await PdfDocument.openFile(pdfPath);
    final paths = <String>[];
    final tempDirectory = await Directory.systemTemp.createTemp('atc_schedule_pdf_');

    try {
      for (var pageNumber = 1; pageNumber <= document.pagesCount; pageNumber++) {
        final page = await document.getPage(pageNumber);
        try {
          // Render at roughly 2x source resolution. WMT schedule tables contain
          // small text, and the higher raster resolution materially improves
          // ML Kit recognition while remaining reasonable for phone memory.
          final rendered = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) continue;

          final file = File('${tempDirectory.path}/page_$pageNumber.png');
          await file.writeAsBytes(rendered.bytes, flush: true);
          paths.add(file.path);
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }

    if (paths.isEmpty) {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
      throw StateError('No PDF pages could be rendered.');
    }

    return paths;
  }

  Future<void> deleteTemporaryImages(Iterable<String> paths) async {
    final parentDirectories = <String>{};
    for (final path in paths) {
      final file = File(path);
      parentDirectories.add(file.parent.path);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    for (final directoryPath in parentDirectories) {
      final directory = Directory(directoryPath);
      if (!directory.path.contains('atc_schedule_pdf_')) continue;
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {}
    }
  }
}
