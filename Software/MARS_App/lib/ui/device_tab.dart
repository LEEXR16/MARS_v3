/// What every device tab has, for the app shell: the tab dot colour, STOP, shutdown and messages.
library;

import 'package:flutter/material.dart';

import '../core/line_device.dart';

abstract class DeviceController {
  String get name;

  /// One line for the welcome screen, e.g. what the device is.
  String get description;

  /// Colour of the dot on the tab.
  Color get statusColor;
  bool get isConnected;

  /// Info / warning / error messages, shown as snack bars.
  Stream<DeviceMessage> get messages;

  /// STOP: the robot holds where it is. Does nothing when not connected.
  void emergencyStop();

  /// Stops motion and recording and disconnects (app closing).
  Future<void> shutdown();

  Widget buildTab();
}
