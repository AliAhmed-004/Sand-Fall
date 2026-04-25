import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfall/models/game_state_dto.dart';
import 'package:sandfall/world.dart';

void main() {
  group('Load/Resume regression tests', () {
    test('sparse save does not merge red across empty cells', () {
      final world = SandWorld(cols: 5, rows: 3);
      const y = 2;

      final leftIdx = y * world.cols;
      final rightIdx = y * world.cols + 2;

      world.gridColorBuffer[leftIdx] = Colors.red.toARGB32();
      world.baseColorIdBuffer[leftIdx] = 0;

      world.gridColorBuffer[rightIdx] = Colors.red.toARGB32();
      world.baseColorIdBuffer[rightIdx] = 0;

      final sparse = SparseGameStateDTO.fromWorld(world);

      expect(sparse.runs.length, 2);
      expect(sparse.runs[0].row, y);
      expect(sparse.runs[0].firstCol, 0);
      expect(sparse.runs[0].runLength, 1);
      expect(sparse.runs[1].row, y);
      expect(sparse.runs[1].firstCol, 2);
      expect(sparse.runs[1].runLength, 1);
    });

    test('cluster rebuild groups adjacent same base color with different shades', () {
      final world = SandWorld(cols: 4, rows: 2);

      final idxA = 1; // x=1, y=0
      final idxB = 2; // x=2, y=0

      world.gridColorBuffer[idxA] = Colors.red.toARGB32();
      world.baseColorIdBuffer[idxA] = 0;

      world.gridColorBuffer[idxB] = Colors.red.shade700.toARGB32();
      world.baseColorIdBuffer[idxB] = 0;

      world.rebuildClusters(world);

      expect(world.clusters.length, 1);
      final cluster = world.clusters.values.single;
      expect(cluster.cells.length, 2);
      expect(world.cellIdMap[idxA], cluster.id);
      expect(world.cellIdMap[idxB], cluster.id);
    });

    test('cluster rebuild does not wrap row edges as neighbors', () {
      final world = SandWorld(cols: 3, rows: 2);

      final idxTopRight = 2; // x=2, y=0
      final idxBottomLeft = 3; // x=0, y=1

      world.gridColorBuffer[idxTopRight] = Colors.blue.toARGB32();
      world.baseColorIdBuffer[idxTopRight] = 4;

      world.gridColorBuffer[idxBottomLeft] = Colors.blue.toARGB32();
      world.baseColorIdBuffer[idxBottomLeft] = 4;

      world.rebuildClusters(world);

      expect(world.clusters.length, 2);
      expect(world.cellIdMap[idxTopRight], isNot(0));
      expect(world.cellIdMap[idxBottomLeft], isNot(0));
      expect(world.cellIdMap[idxTopRight], isNot(world.cellIdMap[idxBottomLeft]));
    });
  });
}
