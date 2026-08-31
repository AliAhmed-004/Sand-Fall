import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:sandfall/config/game_config.dart';
import 'package:sandfall/models/game_state_dto.dart';

/// Service responsible for saving and loading the game state from Hive storage.
///
/// Uses [SparseGameStateDTO] for efficient binary serialization that only stores
/// occupied cells as runs, dramatically reducing I/O overhead.
class SaveGameService {
  static final SaveGameService _instance = SaveGameService._internal();

  factory SaveGameService() {
    return _instance;
  }

  SaveGameService._internal();

  static SaveGameService get instance => _instance;

  late Box _box;
  bool _isSaving = false;
  Uint8List? _pendingData;

  /// Initialize Hive and open the game state box.
  /// Call this once during app initialization.
  Future<void> initialize() async {
    _box = await Hive.openBox(GameConfig.gameStateBox);
  }

  // ─── Regular game slot ───────────────────────────────────────────────────

  Future<void> saveRegularGame(SparseGameStateDTO state, int score) async {
    await _writeSlot(GameConfig.savedGameStateKey, state, score);
  }

  Map<String, dynamic>? loadRegularGame() =>
      _readSlot(GameConfig.savedGameStateKey);

  bool hasRegularGame() => _box.containsKey(GameConfig.savedGameStateKey);

  int? getSavedRegularScore() => _readScore(GameConfig.savedGameStateKey);

  Future<void> deleteRegularGame() async =>
      _box.delete(GameConfig.savedGameStateKey);

  // ─── Daily challenge slot ─────────────────────────────────────────────────

  Future<void> saveDailyGame(SparseGameStateDTO state, int score) async {
    await _writeSlot(GameConfig.savedDailyChallengeKey, state, score);
  }

  Map<String, dynamic>? loadDailyGame() =>
      _readSlot(GameConfig.savedDailyChallengeKey);

  bool hasDailyGame() => _box.containsKey(GameConfig.savedDailyChallengeKey);

  Future<void> deleteDailyGame() async =>
      _box.delete(GameConfig.savedDailyChallengeKey);

  // ─── Internal write/read ──────────────────────────────────────────────────

  Future<void> _writeSlot(
    String key,
    SparseGameStateDTO state,
    int score,
  ) async {
    final bytes = _encodeSparseState(state, score);
    _pendingData = bytes;

    if (_isSaving) return;

    _isSaving = true;
    try {
      while (_pendingData != null) {
        final dataToWrite = _pendingData!;
        _pendingData = null;
        await _box.put(key, dataToWrite);
      }
    } finally {
      _isSaving = false;
    }
  }

  Map<String, dynamic>? _readSlot(String key) {
    final data = _box.get(key);
    if (data == null) return null;

    try {
      final bytes = data as Uint8List;
      final dataView = ByteData.sublistView(bytes);
      final score = dataView.getInt32(6, Endian.little);
      final state = _decodeSparseState(bytes, score);
      if (state == null) return null;
      return {'state': state, 'score': score};
    } catch (e) {
      return null;
    }
  }

  int? _readScore(String key) {
    final data = _box.get(key);
    if (data == null) return null;
    try {
      final bytes = data as Uint8List;
      final dataView = ByteData.sublistView(bytes);
      return dataView.getInt32(6, Endian.little);
    } catch (e) {
      return null;
    }
  }

  /// Encodes sparse game state + score into a compact binary format.
  ///
  /// Format:
  /// - cols (2 bytes)
  /// - rows (2 bytes)
  /// - topRow (2 bytes)
  /// - score (4 bytes)
  /// - numRuns (4 bytes)
  /// - Per run: row(2) + firstCol(2) + runLength(2) + color(4) + baseColorId(1) = 13 bytes
  Uint8List _encodeSparseState(SparseGameStateDTO state, int score) {
    final numRuns = state.runs.length;
    // Header: cols(2) + rows(2) + topRow(2) + score(4) + numRuns(4) = 14 bytes
    // Per run: 13 bytes
    final data = ByteData(14 + numRuns * 13);

    int offset = 0;
    data.setUint16(offset, state.cols, Endian.little);
    offset += 2;
    data.setUint16(offset, state.rows, Endian.little);
    offset += 2;
    data.setUint16(offset, state.topRow, Endian.little);
    offset += 2;
    data.setInt32(offset, score, Endian.little);
    offset += 4;
    data.setInt32(offset, numRuns, Endian.little);
    offset += 4;

    for (final run in state.runs) {
      data.setUint16(offset, run.row, Endian.little);
      offset += 2;
      data.setUint16(offset, run.firstCol, Endian.little);
      offset += 2;
      data.setUint16(offset, run.runLength, Endian.little);
      offset += 2;
      data.setInt32(offset, run.color, Endian.little);
      offset += 4;
      data.setUint8(offset, run.baseColorId);
      offset += 1;
    }

    return data.buffer.asUint8List();
  }

  /// Decodes binary data back into SparseGameStateDTO.
  SparseGameStateDTO? _decodeSparseState(Uint8List bytes, int score) {
    try {
      final data = ByteData.sublistView(bytes);

      int offset = 0;
      final cols = data.getUint16(offset, Endian.little);
      offset += 2;
      final rows = data.getUint16(offset, Endian.little);
      offset += 2;
      final topRow = data.getUint16(offset, Endian.little);
      offset += 2;
      // score is read separately
      offset += 4;
      final numRuns = data.getInt32(offset, Endian.little);
      offset += 4;

      final runs = <SparseCellRun>[];
      for (int i = 0; i < numRuns; i++) {
        final row = data.getUint16(offset, Endian.little);
        offset += 2;
        final firstCol = data.getUint16(offset, Endian.little);
        offset += 2;
        final runLength = data.getUint16(offset, Endian.little);
        offset += 2;
        final color = data.getInt32(offset, Endian.little);
        offset += 4;
        final baseColorId = data.getUint8(offset);
        offset += 1;

        runs.add(
          SparseCellRun(
            row: row,
            firstCol: firstCol,
            runLength: runLength,
            color: color,
            baseColorId: baseColorId,
          ),
        );
      }

      return SparseGameStateDTO(
        cols: cols,
        rows: rows,
        topRow: topRow,
        runs: runs,
      );
    } catch (e) {
      return null;
    }
  }


}
