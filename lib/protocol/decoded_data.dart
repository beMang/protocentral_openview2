/// Structured output from decoding a single packet.
///
/// All fields are optional because different boards produce different
/// subsets of data. Lists may contain multiple samples per packet
/// (e.g., Healthypi PktType 3 carries 8 ECG + 4 RESP samples).
class DecodedData {
  final List<double> ecgSamples;
  final List<double> ecg2Samples;
  final List<double> ecg3Samples;
  final List<double> respSamples;
  final List<double> ppgSamples;

  final int? heartRate;
  final int? respRate;
  final int? spo2;
  final double? temperature;

  /// When log values differ from display values (e.g., ADS1293 divides ECG
  /// by 1000 for logging). If null, use the display samples directly.
  final List<double>? ecgLogSamples;
  final List<double>? ppgLogSamples;
  final List<double>? respLogSamples;

  /// Per-sample validity for PPG channel (MAX30001 BioZ tag).
  /// If null, all PPG samples are considered valid.
  final List<bool>? ppgValidity;

  const DecodedData({
    this.ecgSamples = const [],
    this.ecg2Samples = const [],
    this.ecg3Samples = const [],
    this.respSamples = const [],
    this.ppgSamples = const [],
    this.heartRate,
    this.respRate,
    this.spo2,
    this.temperature,
    this.ecgLogSamples,
    this.ppgLogSamples,
    this.respLogSamples,
    this.ppgValidity,
  });
}
