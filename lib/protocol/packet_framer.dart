/// Encapsulated byte-at-a-time state machine for the ProtoCentral packet protocol.
///
/// Packet format: [0x0A][0xFA][LEN_LSB][LEN_MSB][PKT_TYPE][...PAYLOAD...][0x0B]

/// A fully framed packet received from the serial stream.
class FramedPacket {
  final int pktType;

  /// Payload for pktType 2 (standard data).
  final List<int> data;

  /// Payload for pktType 3 (ECG/RESP, Healthypi only).
  final List<int> ecgRespData;

  /// Payload for pktType 4 (PPG, Healthypi only).
  final List<int> ppgData;

  const FramedPacket({
    required this.pktType,
    this.data = const [],
    this.ecgRespData = const [],
    this.ppgData = const [],
  });
}

typedef OnPacketFramed = void Function(FramedPacket packet);
typedef OnFramerError = void Function(String message);

/// Lightweight diagnostic counters for the framer.
class FramerStats {
  int packetsReceived = 0;
  int packetsDroppedNoEof = 0;
  int packetsDroppedOversize = 0;
  int packetsDroppedUnknownType = 0;
  int packetsDroppedTimeout = 0;
  int resyncs = 0;

  void reset() {
    packetsReceived = 0;
    packetsDroppedNoEof = 0;
    packetsDroppedOversize = 0;
    packetsDroppedUnknownType = 0;
    packetsDroppedTimeout = 0;
    resyncs = 0;
  }

  @override
  String toString() =>
      'FramerStats(ok: $packetsReceived, noEof: $packetsDroppedNoEof, '
      'oversize: $packetsDroppedOversize, unknownType: $packetsDroppedUnknownType, '
      'timeout: $packetsDroppedTimeout, resyncs: $resyncs)';
}

/// Byte-at-a-time state machine that detects packet boundaries and emits
/// complete [FramedPacket] objects via [onPacket].
///
/// Robustness features:
/// - Maximum payload length guard (prevents buffer overflow on corrupted length)
/// - Timeout detection (abandons stale partial packets)
/// - Unknown pktType reporting
/// - Diagnostic counters via [stats]
///
/// Note: SOF re-detection mid-payload was removed because the protocol does
/// not use byte-stuffing. Sensor data (ECG, PPG, etc.) can legitimately
/// contain the bytes 0x0A 0xFA, which caused false resyncs and dropped
/// valid packets. The length-guard + EOF check + timeout provide sufficient
/// error recovery.
///
/// All state is encapsulated — no globals required.
class PacketFramer {
  // Protocol constants
  static const int _sof1 = 0x0A;
  static const int _sof2 = 0xFA;
  static const int _eof = 0x0B;
  static const int _indLen = 2;
  static const int _indLenMsb = 3;
  static const int _indPktType = 4;
  static const int _pktOverhead = 5;

  /// Maximum allowed payload length. Any packet declaring a length above this
  /// is treated as corrupted and discarded. The largest known payload is
  /// Healthypi pktType 3 at ~50 bytes; 500 is generous headroom.
  static const int _maxPayloadLen = 500;

  /// If no byte arrives within this duration while mid-packet, the partial
  /// packet is abandoned and the framer resyncs.
  static const Duration timeoutDuration = Duration(milliseconds: 500);

  // State machine states
  static const int _stateInit = 0;
  static const int _stateSof1Found = 1;
  static const int _stateSof2Found = 2;
  static const int _statePktLenFound = 3;

  // Instance state
  int _state = _stateInit;
  int _pktLen = 0;
  int _posCounter = 0;
  int _pktType = 0;

  int _dataCounter = 0;
  int _ecgRespDataCounter = 0;
  int _ppgDataCounter = 0;

  final List<int> _dataBuffer = List.filled(1000, 0);
  final List<int> _ecgRespBuffer = List.filled(1000, 0);
  final List<int> _ppgBuffer = List.filled(1000, 0);

  /// Timestamp (milliseconds since epoch) of the last byte processed while
  /// inside a packet (state != _stateInit).
  int _lastByteTimeMs = 0;

  final OnPacketFramed onPacket;
  final OnFramerError? onError;

  /// Diagnostic counters. Read these to monitor link health.
  final FramerStats stats = FramerStats();

  PacketFramer({required this.onPacket, this.onError});

  /// Process a chunk of bytes from the serial stream.
  ///
  /// This is the preferred entry point — it timestamps once per chunk instead
  /// of calling DateTime.now() for every byte, which avoids unnecessary
  /// overhead at high data rates.
  void processChunk(List<int> data) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < data.length; i++) {
      _processByte(data[i], nowMs);
    }
    // Update timestamp to actual wall time AFTER processing. Without this,
    // the next chunk's timeout measurement would include the processing time
    // of THIS chunk (setState, chart rendering, etc.), causing false timeouts
    // when the app is busy rendering real-time waveforms.
    if (_state != _stateInit) {
      _lastByteTimeMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// Process a single byte. Prefer [processChunk] when you have multiple bytes.
  void processByte(int rxch) {
    _processByte(rxch, DateTime.now().millisecondsSinceEpoch);
  }

  void _processByte(int rxch, int nowMs) {
    // --- Timeout guard ---
    // If we're mid-packet and too much time has passed since the last byte,
    // the current packet is stale — abandon it and resync.
    if (_state != _stateInit) {
      if (_lastByteTimeMs > 0 &&
          (nowMs - _lastByteTimeMs) > timeoutDuration.inMilliseconds) {
        stats.packetsDroppedTimeout++;
        onError?.call(
            'Packet timeout: no data for ${nowMs - _lastByteTimeMs}ms '
            '(state=$_state, pktLen=$_pktLen, pos=$_posCounter)');
        _resetState();
        // Fall through — process this byte as a fresh _stateInit byte.
      }
      _lastByteTimeMs = nowMs;
    }

    switch (_state) {
      case _stateInit:
        if (rxch == _sof1) {
          _state = _stateSof1Found;
          _lastByteTimeMs = nowMs;
        }
        break;

      case _stateSof1Found:
        if (rxch == _sof2) {
          _state = _stateSof2Found;
        } else {
          _state = _stateInit;
        }
        break;

      case _stateSof2Found:
        _state = _statePktLenFound;
        _pktLen = rxch;
        _posCounter = _indLen;
        _dataCounter = 0;
        _ecgRespDataCounter = 0;
        _ppgDataCounter = 0;
        break;

      case _statePktLenFound:
        _posCounter++;
        if (_posCounter < _pktOverhead) {
          // Reading header bytes
          if (_posCounter == _indLenMsb) {
            _pktLen = (rxch << 8) | _pktLen;

            // --- Length guard ---
            if (_pktLen > _maxPayloadLen) {
              stats.packetsDroppedOversize++;
              onError?.call(
                  'Packet length $_pktLen exceeds max $_maxPayloadLen — dropping');
              _resetState();
              break;
            }
          } else if (_posCounter == _indPktType) {
            _pktType = rxch;
            // Early pktType validation — reject before consuming the full
            // payload.  Without this, a false SOF (0x0A 0xFA appearing in
            // sensor data) consumes pktLen+1 bytes of real data as "payload"
            // before the EOF check fails, causing long cascading failures.
            if (_pktType != 2 && _pktType != 3 && _pktType != 4 && _pktType != 5) {
              stats.packetsDroppedUnknownType++;
              stats.resyncs++;
              _resetState();
              break;
            }
          }
        } else if (_posCounter < _pktOverhead + _pktLen + 1) {
          // --- Payload bytes ---
          // No mid-payload SOF re-detection: the protocol does not use
          // byte-stuffing, so sensor data can legitimately contain 0x0A 0xFA.
          // Robustness is provided by the length-guard, EOF check, and timeout.
          if ((_pktType == 2 || _pktType == 5) && _dataCounter < _dataBuffer.length) {
            _dataBuffer[_dataCounter++] = rxch;
          } else if (_pktType == 3 &&
              _ecgRespDataCounter < _ecgRespBuffer.length) {
            _ecgRespBuffer[_ecgRespDataCounter++] = rxch;
          } else if (_pktType == 4 && _ppgDataCounter < _ppgBuffer.length) {
            _ppgBuffer[_ppgDataCounter++] = rxch;
          }
        } else {
          // All data received — check stop byte
          if (rxch == _eof) {
            if (_pktType == 2 || _pktType == 3 || _pktType == 4 || _pktType == 5) {
              stats.packetsReceived++;
              onPacket(FramedPacket(
                pktType: _pktType,
                data:
                    List<int>.from(_dataBuffer.getRange(0, _dataCounter)),
                ecgRespData: List<int>.from(
                    _ecgRespBuffer.getRange(0, _ecgRespDataCounter)),
                ppgData:
                    List<int>.from(_ppgBuffer.getRange(0, _ppgDataCounter)),
              ));
            } else {
              stats.packetsDroppedUnknownType++;
              onError?.call('Unknown pktType: $_pktType — packet discarded');
            }
          } else {
            stats.packetsDroppedNoEof++;
            onError?.call(
                'Expected EOF (0x${_eof.toRadixString(16)}), '
                'got 0x${rxch.toRadixString(16)} — packet discarded');
            stats.resyncs++;
          }
          _resetState();
          // SOF recovery: if the byte that failed the EOF check happens to
          // be 0x0A, it may be the start of the very next packet.  Transition
          // to SOF1Found so we don't miss a real packet boundary.
          if (rxch == _sof1) {
            _state = _stateSof1Found;
            _lastByteTimeMs = nowMs;
          }
        }
        break;
    }
  }

  /// Reset the framer state (e.g., on reconnect).
  void reset() {
    _resetState();
    stats.reset();
  }

  void _resetState() {
    _state = _stateInit;
    _pktLen = 0;
    _posCounter = 0;
    _pktType = 0;
    _dataCounter = 0;
    _ecgRespDataCounter = 0;
    _ppgDataCounter = 0;
    _lastByteTimeMs = 0;
  }
}
