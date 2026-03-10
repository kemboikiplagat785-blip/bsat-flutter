import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

  static const MethodChannel _channel = MethodChannel('bsat_logger');
  static bool _initialized = false;
  static final BsatLogger _globalLogger = BsatLogger(tag: 'Global');
  static File? logFile;

  /// Initialize file logging
  static Future<void> initFileLogging() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      logFile = File('${directory.path}/bsat_logs.txt');
      // If file is too large (>5MB), clear it to prevent endless growth
      if (await logFile!.exists() && await logFile!.length() > 5 * 1024 * 1024) {
        await logFile!.writeAsString('');
      }
    } catch (e) {
      debugPrint("Could not initialize log file: $e");
    }
  }

  /// Initialize global error and log interceptors.
  /// Wraps [runApp] or block inside [runZonedGuarded] to catch print statements.
  static void captureLogs() {
    if (_initialized) return;
    _initialized = true;

    // 1. Capture Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _globalLogger.fatal(details.exceptionAsString(), details.stack);
    };

    // 2. Capture async Dart errors not caught by Flutter
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _globalLogger.error(error.toString(), stack);
      return true;
    };

    // 3. Listen to native logs from Kotlin/Swift
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'logFromNative') {
        final args = call.arguments as Map<dynamic, dynamic>;
        final levelStr = args['level'] as String?;
        final message = args['message'] as String? ?? '';
        final nativeTag = args['tag'] as String?;

        final level = _parseLevel(levelStr);
        final logger = BsatLogger(tag: 'Native${nativeTag != null ? ':$nativeTag' : ''}');
        logger._log(level, message, null);
      }
    });
  }

  /// Run app inside a zone that captures all `print` statements.
  static R runZonedWithLogs<R>(R Function() body) {
    return runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          _globalLogger.debug(line);
          // Optional: uncomment below to also print natively
          // parent.print(zone, line);
        },
      ),
    );
  }

  static LogLevel _parseLevel(String? levelStr) {
    switch (levelStr?.toLowerCase()) {
      case 'info': return LogLevel.info;
      case 'warn': return LogLevel.warn;
      case 'error': return LogLevel.error;
      case 'fatal': return LogLevel.fatal;
      case 'debug': 
      default: return LogLevel.debug;
    }
  }

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
    // Format timestamp as HH:mm:ss.ms
    final timeStr = 
        "${event.timestamp.hour.toString().padLeft(2, '0')}:"
        "${event.timestamp.minute.toString().padLeft(2, '0')}:"
        "${event.timestamp.second.toString().padLeft(2, '0')}."
        "${event.timestamp.millisecond.toString().padLeft(3, '0')}";
        
    final buffer = StringBuffer()
      ..write('[$timeStr] ')
      ..write('[${event.level.name.toUpperCase()}] ');
    if (event.tag != null && event.tag!.isNotEmpty) {
      buffer.write('[${event.tag}] ');
    }
    buffer.write(event.message);
    if (event.data != null) {
      buffer.write(' | ${event.data}');
    }
    final msg = buffer.toString();
    debugPrint(msg);

    // Save to file if initialized
    if (logFile != null) {
      try {
        logFile!.writeAsStringSync('$msg\n', mode: FileMode.append);
      } catch (e) {
        // ignore errors writing to file
      }
    }
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
