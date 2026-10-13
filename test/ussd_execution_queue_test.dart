import 'dart:async';

import 'package:bsat/services/phone_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('USSD requests wait for the active request and run in arrival order',
      () async {
    final queue = UssdExecutionQueue();
    final firstStarted = Completer<void>();
    final finishFirst = Completer<void>();
    final order = <String>[];
    var active = 0;
    var maxActive = 0;

    Future<void> execute(String name) async {
      active++;
      if (active > maxActive) maxActive = active;
      order.add('$name:start');
      if (name == 'A') {
        firstStarted.complete();
        await finishFirst.future;
      }
      order.add('$name:finish');
      active--;
    }

    final a = queue.run(() => execute('A'));
    await firstStarted.future;
    final b = queue.run(() => execute('B'));
    final c = queue.run(() => execute('C'));

    expect(order, ['A:start']);
    expect(queue.pendingCount, 3);
    finishFirst.complete();
    await Future.wait([a, b, c]);

    expect(order, [
      'A:start',
      'A:finish',
      'B:start',
      'B:finish',
      'C:start',
      'C:finish',
    ]);
    expect(maxActive, 1);
    expect(queue.pendingCount, 0);
  });

  test('a failed request releases the queue for the next request', () async {
    final queue = UssdExecutionQueue();
    var secondRan = false;
    final first = queue.run<void>(() async => throw StateError('failed'));
    final second = queue.run(() async => secondRan = true);

    await expectLater(first, throwsA(isA<StateError>()));
    await second;
    expect(secondRan, isTrue);
    expect(queue.pendingCount, 0);
  });
}
