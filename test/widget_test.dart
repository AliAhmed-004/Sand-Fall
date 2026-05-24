// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfall/world.dart';

void main() {
  test('primeDirtyTracking + syncGridNow should populate lastDirtyCellIndices', () {
    const cols = 5;
    const rows = 5;
    final world = SandWorld(cols: cols, rows: rows);

    // Pick a cell and mark it occupied in the raw buffers to simulate a loaded save
    final int testX = 2;
    final int testY = rows - 1; // bottom row
    final int idx = testY * cols + testX;

    world.gridColorBuffer[idx] = const Color(0xFF0000FF).toARGB32(); // arbitrary color
    world.baseColorIdBuffer[idx] = 1; // valid base color id

    // Rebuild clusters from the raw buffers (similar to load flow)
    world.rebuildClusters(world);

    // Prime dirty-tracking (the fix we added)
    world.primeDirtyTracking();

    // Now run a sync which should clear previous-frame cells and populate lastDirtyCellIndices
    world.syncGridNow();

    expect(world.lastDirtyCellCount, greaterThan(0));

    bool found = false;
    for (int i = 0; i < world.lastDirtyCellCount; i++) {
      if (world.lastDirtyCellIndices[i] == idx) {
        found = true;
        break;
      }
    }
    expect(found, isTrue, reason: 'Expected lastDirtyCellIndices to contain the test index');
  });
}
