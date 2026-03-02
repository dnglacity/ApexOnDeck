import 'package:flutter/material.dart';

extension ControllerListDispose on List<TextEditingController> {
  void disposeAll() {
    for (final c in this) {
      c.dispose();
    }
  }
}
