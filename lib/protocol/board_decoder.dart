import 'decoded_data.dart';
import 'packet_framer.dart';
import 'byte_utils.dart';

/// Abstract interface for board-specific payload decoding.
abstract class BoardDecoder {
  /// Decode a framed packet into structured data.
  /// Returns null if this packet type is not handled by this decoder.
  DecodedData? decode(FramedPacket packet);
}

/// Returns the appropriate decoder for the given board name,
/// or null if the board name is not recognized.
BoardDecoder? decoderForBoard(String boardName) {
  switch (boardName) {
    case 'Healthypi (USB)':
      return HealthypiDecoder();
    case 'Healthypi 6 (USB)':
      return Healthypi6Decoder();
    case 'ADS1292R Breakout/Shield (USB)':
      return ADS1292RDecoder();
    case 'ADS1293 Breakout/Shield (USB)':
      return ADS1293Decoder();
    case 'AFE4490 Breakout/Shield (USB)':
    case 'Sensything Ox (USB)':
      return AFE4490Decoder();
    case 'MAX86150 Breakout (USB)':
      return MAX86150Decoder();
    case 'Pulse Express (USB)':
      return PulseExpressDecoder();
    case 'tinyGSR Breakout (USB)':
      return TinyGSRDecoder();
    case 'MAX30003 ECG Breakout (USB)':
      return MAX30003Decoder();
    case 'MAX30001 ECG & BioZ Breakout (USB)':
      return MAX30001Decoder();
    case 'Move 2 (USB)':
      return Move2Decoder();
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Concrete decoders
// ---------------------------------------------------------------------------

/// Healthypi (USB) — 128 Hz, handles pktTypes 2, 3, and 4.
class HealthypiDecoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    switch (packet.pktType) {
      case 3:
        return _decodeEcgResp(packet.ecgRespData);
      case 4:
        return _decodePpg(packet.ppgData);
      case 2:
        return _decodeStandard(packet.data);
      default:
        return null;
    }
  }

  DecodedData _decodeEcgResp(List<int> p) {
    final ecg = List.generate(8, (i) => readInt32LE(p, i * 4).toDouble());
    final resp = List.generate(4, (i) => readInt32LE(p, 32 + i * 4).toDouble());
    return DecodedData(
      ecgSamples: ecg,
      respSamples: resp,
      heartRate: p[48],
      respRate: p[49],
    );
  }

  DecodedData _decodePpg(List<int> p) {
    // 8 x 16-bit unsigned PPG samples
    final ppg = List.generate(8, (i) => readUint16LE(p, i * 2).toDouble());
    // Logging uses toSigned(32) on the uint16 value
    final ppgLog =
        List.generate(8, (i) => readUint16LE(p, i * 2).toSigned(32).toDouble());
    return DecodedData(
      ppgSamples: ppg,
      ppgLogSamples: ppgLog,
      spo2: p[16],
      temperature: readUint16LE(p, 17) / 100.0,
    );
  }

  DecodedData _decodeStandard(List<int> d) {
    final ecg = readInt32LE(d, 0);
    final resp = readInt32LE(d, 4);
    final ppg = readInt32LE(d, 9); // Note: offset 9, not 8
    return DecodedData(
      ecgSamples: [ecg.toDouble()],
      respSamples: [resp.toDouble()],
      ppgSamples: [ppg.toDouble()],
      // Logging: ECG signed, PPG/RESP raw (unsigned interpretation)
      ecgLogSamples: [ecg.toDouble()],
      ppgLogSamples: [
        (d[9] | d[10] << 8 | d[11] << 16 | d[12] << 24).toDouble()
      ],
      respLogSamples: [
        (d[4] | d[5] << 8 | d[6] << 16 | d[7] << 24).toDouble()
      ],
      spo2: d[19],
      heartRate: d[20],
      respRate: d[21],
      temperature: readUint16LE(d, 17) / 100.0,
    );
  }
}

/// Healthypi 6 (USB) — 500 Hz, pktType 2, 5 channels.
class Healthypi6Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    final ecg1 = readInt32LE(d, 0).toDouble();
    final ecg2 = readInt32LE(d, 4).toDouble();
    final ecg3 = readInt32LE(d, 8).toDouble();
    final resp = readInt32LE(d, 12).toDouble();

    // PPG only valid if d[24] != 0
    final ppgValid = d[24] != 0;
    final ppg =
        ppgValid ? readUint32LE(d, 16).toDouble() : null;

    // HR: original code used mixed buffers (likely a bug).
    // Reading both bytes from the data buffer instead.
    final hr = readUint16LE(d, 25);

    return DecodedData(
      ecgSamples: [ecg1],
      ecg2Samples: [ecg2],
      ecg3Samples: [ecg3],
      respSamples: [resp],
      ppgSamples: ppg != null ? [ppg] : [],
      ppgValidity: [ppgValid],
      heartRate: hr,
      spo2: d[27],
      respRate: d[28],
      temperature: readUint16LE(d, 29) / 100.0,
    );
  }
}

/// ADS1292R Breakout/Shield (USB) — 128 Hz, 16-bit samples.
class ADS1292RDecoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    // 16-bit sign-extended via shift pattern
    final ecg = signExtend16(readUint16LE(d, 0));
    final resp = signExtend16(readUint16LE(d, 2));
    final hr = signExtend16(readUint16LE(d, 4));
    final rr = signExtend16(readUint16LE(d, 6));

    return DecodedData(
      ecgSamples: [ecg.toSigned(16).toDouble()],
      respSamples: [resp.toSigned(16).toDouble()],
      heartRate: hr,
      respRate: rr,
    );
  }
}

/// ADS1293 Breakout/Shield (USB) — 128 Hz, 3 channels 32-bit.
class ADS1293Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    final ecg = readInt32LE(d, 0).toDouble();
    final resp = readInt32LE(d, 4).toDouble();
    final ppg = readInt32LE(d, 8).toDouble();

    return DecodedData(
      ecgSamples: [ecg],
      respSamples: [resp],
      ppgSamples: [ppg],
      ecgLogSamples: [ecg / 1000.0],
    );
  }
}

/// AFE4490 Breakout/Shield (USB) and Sensything Ox (USB) — 128 Hz.
class AFE4490Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    // Assembled as 32-bit but used unsigned (no toSigned)
    final ecg = (d[0] | d[1] << 8 | d[2] << 16 | d[3] << 24).toDouble();
    final ppg = (d[4] | d[5] << 8 | d[6] << 16 | d[7] << 24).toDouble();

    return DecodedData(
      ecgSamples: [ecg],
      ppgSamples: [ppg],
      spo2: d[8],
      heartRate: d[9],
    );
  }
}

/// MAX86150 Breakout (USB) — 128 Hz, 3 channels 16-bit sign-extended.
class MAX86150Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    // Sign-extend then display: ECG uses toSigned(16), others use raw
    final value1 = signExtend16(readUint16LE(d, 0));
    final value2 = signExtend16(readUint16LE(d, 2));
    final value3 = signExtend16(readUint16LE(d, 4));

    return DecodedData(
      ecgSamples: [value1.toSigned(16).toDouble()],
      respSamples: [value2.toDouble()],
      ppgSamples: [value3.toDouble()],
    );
  }
}

/// Pulse Express (USB) — 128 Hz, 2 channels 16-bit unsigned.
class PulseExpressDecoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    final ecg = readUint16LE(d, 0).toDouble();
    final resp = readUint16LE(d, 2).toDouble();

    return DecodedData(
      ecgSamples: [ecg],
      respSamples: [resp],
    );
  }
}

/// tinyGSR Breakout (USB) — 128 Hz, single 16-bit channel.
class TinyGSRDecoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;

    final raw = readUint16LE(packet.data, 0);
    return DecodedData(
      ecgSamples: [raw.toSigned(16).toDouble()],
      ecgLogSamples: [raw.toDouble()],
    );
  }
}

/// MAX30003 ECG Breakout (USB) — 128 Hz, ECG 32-bit + computed vitals.
class MAX30003Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    final ecg = readInt32LE(d, 0).toDouble();
    final computedVal1 = readInt32LE(d, 4); // displayed as respRate
    final computedVal2 = readInt32LE(d, 8); // displayed as heartRate

    return DecodedData(
      ecgSamples: [ecg],
      ecgLogSamples: [ecg / 1000.0],
      heartRate: computedVal2,
      respRate: computedVal1,
    );
  }
}

/// MAX30001 ECG & BioZ Breakout (USB) — 128 Hz, ECG + BioZ with tag.
class MAX30001Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 2) return null;
    final d = packet.data;

    final ecg = readInt32LE(d, 0).toDouble();
    final bioz = readInt32LE(d, 4).toDouble();
    final tag = d[8];

    return DecodedData(
      ecgSamples: [ecg],
      ppgSamples: [bioz],
      ppgValidity: [tag == 0],
    );
  }
}

/// Move 2 (USB) — 100 Hz, pktType 5.
/// Payload layout (26 bytes, all little-endian):
///   [0-3]   ECG       int32   (AS7058 ECG channel)
///   [4-7]   PPG Green uint32  (AS7058 primary PPG)
///   [8-11]  PPG Red   uint32  (AS7058 SpO2 R/IR)
///   [12-15] PPG IR    uint32  (AS7058 SpO2 R/IR)
///   [16-19] GSR       uint32  (AS7058 skin conductance, nS)
///   [20-21] Temp      int16   (AS6221 degC × 100)
///   [22]    SpO2      uint8   (0 = N/A)
///   [23]    HR        uint8   (bpm, 0 = N/A)
///   [24]    RR        uint8   (rpm, 0 = N/A)
///   [25]    Flags     uint8   (bit0: ECG lead-off)
///
/// Channel mapping:
///   ecgSamples  → ECG
///   ppgSamples  → PPG Green
///   respSamples → PPG Red   (reused for second PPG waveform)
///   ecg2Samples → PPG IR    (reused for third PPG waveform)
///   ecg3Samples → GSR
class Move2Decoder extends BoardDecoder {
  @override
  DecodedData? decode(FramedPacket packet) {
    if (packet.pktType != 5) return null;
    final d = packet.data;

    final ecg = readInt32LE(d, 0).toDouble();
    final ppgGreen = readUint32LE(d, 4).toDouble();
    final ppgRed = readUint32LE(d, 8).toDouble();
    final ppgIR = readUint32LE(d, 12).toDouble();
    final gsr = readUint32LE(d, 16).toDouble();

    return DecodedData(
      ecgSamples: [ecg],
      ppgSamples: [ppgGreen],
      respSamples: [ppgRed],
      ecg2Samples: [ppgIR],
      ecg3Samples: [gsr],
      heartRate: d[23],
      spo2: d[22],
      respRate: d[24],
      temperature: readInt16LE(d, 20) / 100.0,
    );
  }
}
