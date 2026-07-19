/// Which bottom-nav tab is showing. Lives above `MaterialApp` rather than
/// inside `BorgShell` so that modal sheets can reach it: a bottom sheet is
/// pushed on the root navigator, so its context descends from *above* the
/// shell and cannot see anything the shell provides.
library;

import 'package:flutter/foundation.dart';

class BorgTabs extends ChangeNotifier {
  static const home = 0;
  static const camera = 1;
  static const radio = 2;
  static const log = 3;

  int _index = home;
  int get index => _index;

  void goTo(int i) {
    if (i == _index) return;
    _index = i;
    notifyListeners();
  }
}
