import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/playback/error_gate.dart';

void main() {
  test('an error arriving during recovery is handled afterwards, not dropped', () async {
    final handled = <String>[];
    final release = Completer<void>();
    late SerialErrorGate<String> gate;
    gate = SerialErrorGate<String>((e) async {
      handled.add('start $e');
      if (e == 'first') await release.future; // recovery in progress…
      handled.add('end $e');
    });

    final first = gate.report('first');
    await Future<void>.delayed(Duration.zero);
    expect(gate.isRunning, isTrue);
    // …the replacement source fails while we are still switching to it.
    unawaited(gate.report('replacement failed'));
    expect(handled, ['start first'], reason: 'not run concurrently');

    release.complete();
    await first;
    expect(handled, ['start first', 'end first', 'start replacement failed', 'end replacement failed']);
    expect(gate.isRunning, isFalse);
  });

  test('only the latest pending error is kept', () async {
    final handled = <int>[];
    final release = Completer<void>();
    final gate = SerialErrorGate<int>((e) async {
      handled.add(e);
      if (e == 1) await release.future;
    });
    final first = gate.report(1);
    await Future<void>.delayed(Duration.zero);
    unawaited(gate.report(2));
    unawaited(gate.report(3));
    release.complete();
    await first;
    expect(handled, [1, 3]);
  });

  test('a failing recovery still releases the gate', () async {
    var calls = 0;
    final gate = SerialErrorGate<int>((e) async {
      calls++;
      throw StateError('boom');
    });
    await expectLater(gate.report(1), throwsStateError);
    expect(gate.isRunning, isFalse);
    await expectLater(gate.report(2), throwsStateError);
    expect(calls, 2);
  });
}
