// Line parsing, the device's line framing, the model and a render of both screens with fake data.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_app/core/line_device.dart';
import 'package:mars_app/devices/mars/mars_protocol.dart';
import 'package:mars_app/main.dart';
import 'package:mars_app/ui/tabs/mars_tab.dart';

// Lines exactly as Firmware_SOLO_v2 prints them
const dLine = 'D,123456,HOLD,0,90.12,0.3,6.215,4.32,31,0,100.0,100.0,6.200,150.0,90.00,0,12.50,-48.20,3.10,31,1';
const mLine = 'M,123460,1,0,0,1,0,1,2251,3114,1627,15';
const lLine = 'L,123470,10.100,12.200,9.900,11.800';
const pLine = 'P,offset=0.12345,dir=1,kt=1.4400,zero_ok=1,a_lever=6.206,lever_ok=1,a_arm=0.000,arm_ok=0,'
    'enc_zero_ok=1,win_lo=60.0,win_hi=120.0,win_c=90.0,kp_center=5.0,bt=1,bt_drop=0,boot=nan';

void main() {
  test('D line', () {
    final s = parseD(dLine.substring(2), 1.0)!;
    expect(s.mode, 'HOLD');
    expect(s.theta, closeTo(90.12, 1e-9));
    expect(s.fault, 0);
    expect(s.on, isTrue);
    // enc 31 = 0b011111: all three usable, link fresh, E1 magnet warning
    expect(s.allEncOk, isTrue);
    expect(s.encWarn(0), isTrue);
    expect(s.encWarn(1), isFalse);
    expect(s.joints, [12.5, -48.2, 3.1]);
    expect(parseD('1,2,3', 0), isNull);
  });

  test('M, L, P lines and COP', () {
    final h = parseM(mLine.substring(2))!;
    expect(h.brakeEngaged, isFalse); // relay bit 0 ON = released
    expect(h.relay(rCfg), isFalse);
    expect(h.motorPowered, isTrue);
    expect(h.raw(1), 3114);
    final l = parseL(lLine.substring(2))!;
    expect(l, [10.1, 12.2, 9.9, 11.8]);
    final (w, x, y) = weightCop(l);
    expect(w, closeTo(44.0, 1e-9));
    expect(x, closeTo(((12.2 + 11.8) - (10.1 + 9.9)) / 44.0 * bHalfMm, 1e-9));
    expect(y, closeTo(((10.1 + 12.2) - (9.9 + 11.8)) / 44.0 * lHalfMm, 1e-9));
    final p = parseP(pLine.substring(2));
    expect(p['kp_center'], 5.0);
    expect(p['boot']!.isNaN, isTrue);
    expect(faultText(2 | 8, 0), 'CAN LOST · TORQUE');
  });

  test('device framing: split lines, partial packets, state', () {
    final c = MarsController();
    final d = c.device;
    // a BLE notify can split a line anywhere
    final bytes = utf8.encode('$pLine\n$dLine\r\n$mLine\n${lLine.substring(0, 10)}');
    d.feed(bytes.sublist(0, 37));
    d.feed(bytes.sublist(37));
    d.feed(utf8.encode('${lLine.substring(10)}\nI,FAULT over torque\n'));
    expect(d.params['zero_ok'], 1);
    expect(d.homeSet, isTrue);
    expect(d.latest!.theta, closeTo(90.12, 1e-9));
    expect(d.hub!.raw(0), 2251);
    expect(d.loads, [10.1, 12.2, 9.9, 11.8]);
    expect(d.log.last, 'FAULT over torque');
  });

  Future<void> pumpApp(WidgetTester tester, MarsController c) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MarsApp(controllers: [c]));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('welcome screen and MARS tab render with live fake data', (tester) async {
    final c = MarsController();
    c.device.debugFakeLink = true;
    c.device.state = ConnState.connected;
    await pumpApp(tester, c);
    expect(find.text('MACHINE'), findsOneWidget);
    await tester.tap(find.text('MACHINE'));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 8; i++) {
      c.device.feed(utf8.encode('$dLine\n$mLine\n$lLine\n${i == 0 ? '$pLine\n' : ''}'));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('HOLD'), findsWidgets);
    expect(find.textContaining('MODE HOLD'), findsOneWidget);
    expect(find.text('HOME ✓'), findsWidgets);
    expect(find.text('Lever angle θ1'.toUpperCase()), findsOneWidget);
    for (final page in ['ASSIST', 'SETUP', 'CONTROL']) {
      await tester.tap(find.text(page));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    // stop the periodic timers before the test ends
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
