import 'dart:convert';
import 'dart:io';

class StorageException implements Exception {
  final String detail;
  final Object? cause;

  const StorageException(this.detail, [this.cause]);

  @override
  String toString() =>
      'StorageException: $detail${cause == null ? '' : ' ($cause)'}';
}

/// Short, privacy-safe description of a storage failure: the operation and
/// OS error, never file contents. Paths are app-private and not secret.
String describeStorageError(Object error) {
  if (error is FileSystemException) {
    final os = error.osError;
    return '${error.runtimeType}: ${error.message}'
        '${os == null ? '' : ' (OS error ${os.errorCode}: ${os.message})'}';
  }
  return error.runtimeType.toString();
}

/// Pending atomic writes per path. Writes to one file run strictly in call
/// order, so two writers never share the temp file and an older snapshot
/// can never replace a newer one.
final Map<String, Future<void>> _writeQueues = {};

/// Replaces [file] with [bytes] so readers see either the old or the new
/// content: write a sibling temp file, flush it to disk, then rename.
Future<void> writeFileAtomically(File file, List<int> bytes) {
  final key = file.absolute.path;
  final previous = _writeQueues[key] ?? Future<void>.value();
  final write = previous.then((_) => _replace(file, bytes));
  final tail = write.then((_) {}, onError: (_) {});
  _writeQueues[key] = tail;
  tail.then((_) {
    if (identical(_writeQueues[key], tail)) _writeQueues.remove(key);
  });
  return write;
}

Future<void> _replace(File file, List<int> bytes) async {
  final temp = File('${file.path}.tmp');
  try {
    final raf = await temp.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }
    await temp.rename(file.path);
  } catch (error) {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {}
    throw StorageException(
      'Could not write ${file.uri.pathSegments.last}: '
      '${describeStorageError(error)}',
      error,
    );
  }
}

Future<void> writeJsonAtomically(File file, Object? json) =>
    writeFileAtomically(file, utf8.encode(jsonEncode(json)));

/// Returns null when the file does not exist. Throws [StorageException] when
/// it exists but cannot be parsed, so corruption is never mistaken for
/// "empty".
Future<Object?> readJsonFile(File file) async {
  if (!await file.exists()) return null;
  try {
    return jsonDecode(await file.readAsString());
  } catch (error) {
    throw StorageException(
      'Could not read ${file.uri.pathSegments.last}',
      error,
    );
  }
}

/// Append-only, line-oriented journal. A line is committed once
/// [append] returns: the bytes were written and flushed to disk.
class JournalFile {
  final File file;
  RandomAccessFile? _raf;

  JournalFile(this.file);

  /// Reads committed lines. A trailing partial line (from a write torn by a
  /// crash) is not committed: it is ignored and truncated away.
  Future<List<String>> readCommittedLines() async {
    if (!await file.exists()) return const [];
    final bytes = await file.readAsBytes();
    final lastNewline = bytes.lastIndexOf(10);
    final committedLength = lastNewline + 1;
    if (committedLength < bytes.length) {
      final raf = await file.open(mode: FileMode.append);
      try {
        await raf.truncate(committedLength);
        await raf.flush();
      } finally {
        await raf.close();
      }
    }
    if (committedLength == 0) return const [];
    return utf8
        .decode(bytes.sublist(0, committedLength), allowMalformed: false)
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> append(String line) async {
    if (line.contains('\n')) throw ArgumentError('line contains newline');
    try {
      final raf = _raf ??= await file.open(mode: FileMode.append);
      await raf.writeFrom(utf8.encode('$line\n'));
      await raf.flush();
    } catch (error) {
      await close();
      throw StorageException('Could not append to journal', error);
    }
  }

  Future<void> rewrite(List<String> lines) async {
    await close();
    await writeFileAtomically(
      file,
      utf8.encode(lines.map((l) => '$l\n').join()),
    );
  }

  Future<void> close() async {
    final raf = _raf;
    _raf = null;
    try {
      await raf?.close();
    } catch (_) {}
  }
}
