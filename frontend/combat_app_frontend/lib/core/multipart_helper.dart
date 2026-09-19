import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

/// Builds a web-safe [MultipartFile] from an [XFile].
///
/// Two real bugs this fixes, both hit in testing:
/// 1. `MultipartFile.fromFile(path)` shells out to `dart:io`, which throws
///    "Unsupported operation: MultipartFile is only supported where dart:io
///    is available" on Flutter Web — reading bytes instead works on every
///    platform (web, desktop, mobile).
/// 2. `MultipartFile.fromBytes(bytes, filename: ...)` on its own does NOT
///    infer a content type from the filename — Dio defaults the part to
///    `application/octet-stream`, which the backend's image-type validator
///    (`file_validation.py`) then rejects outright. The content type has to
///    be set explicitly.
Future<MultipartFile> multipartFromXFile(XFile file) async {
  final bytes = await file.readAsBytes();
  return MultipartFile.fromBytes(
    bytes,
    filename: file.name.isNotEmpty ? file.name : 'upload.jpg',
    contentType: MediaType.parse(_guessMimeType(file)),
  );
}

String _guessMimeType(XFile file) {
  if (file.mimeType != null && file.mimeType!.isNotEmpty) {
    return file.mimeType!;
  }
  final ext = file.name.split('.').last.toLowerCase();
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'avi':
      return 'video/x-msvideo';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}
