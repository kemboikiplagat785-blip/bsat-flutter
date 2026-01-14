import 'package:flutter/foundation.dart';

/// Lightweight logger with leveled output and pluggable sinks.
///
/// Usage:
/// ```dart
/// final log = BsatLogger(tag: 'Auth', minLevel: LogLevel.info);
/// log.debug('Won\'t show');
/// log.info('User logged in', {'uid': uid});
/// ```
class BsatLogger {
  BsatLogger({
    this.tag,
    this.minLevel = LogLevel.debug,
    LogSink? sink,
  }) : _sink = sink ?? defaultSink;

  final String? tag;
  final LogLevel minLevel;
  final LogSink _sink;

  void debug(String message, [Object? data]) =>
      _log(LogLevel.debug, message, data);
  void info(String message, [Object? data]) => _log(LogLevel.info, message, data);
  void warn(String message, [Object? data]) => _log(LogLevel.warn, message, data);
  void error(String message, [Object? data]) =>
      _log(LogLevel.error, message, data);
  void fatal(String message, [Object? data]) =>
      _log(LogLevel.fatal, message, data);

  void _log(LogLevel level, String message, Object? data) {
    if (level.index < minLevel.index) return;
    final event = LogEvent(
      level: level,
      message: message,
      tag: tag,
      data: data,
      timestamp: DateTime.now(),
    );
    _sink(event);
  }

  static void defaultSink(LogEvent event) {
    final buffer = StringBuffer()
      ..write('[${event.timestamp.toIso8601String()}] ')
      ..write('[${event.level.name.toUpperCase()}] ');
    if (event.tag != null && event.tag!.isNotEmpty) {
      buffer.write('[${event.tag}] ');
    }
    buffer.write(event.message);
    if (event.data != null) {
      buffer.write(' | ${event.data}');
    }
    debugPrint(buffer.toString());
  }
}

/// Log severity.
enum LogLevel { debug, info, warn, error, fatal }

/// Immutable log event used by sinks.
class LogEvent {
  const LogEvent({
    required this.level,
    required this.message,
    required this.timestamp,
    this.tag,
    this.data,
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final String? tag;
  final Object? data;
}

/// Sink signature for handling log events (e.g., send to file/remote/console).
typedef LogSink = void Function(LogEvent event);
