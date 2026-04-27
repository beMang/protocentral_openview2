import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'protocol/protocol.dart';
import 'utils/generic_plot.dart';
import 'globals.dart';

class UartSerialPage extends StatefulWidget {
  @override
  State<UartSerialPage> createState() => _UartSerialPageState();
}

class _UartSerialPageState extends State<UartSerialPage> {
  late final PacketFramer _framer;
  late final BoardDecoder? _decoder;

  Process? _rootReaderProcess;
  StreamSubscription<List<int>>? _rootStdoutSub;
  StreamSubscription<String>? _rootStderrSub;
  String _status = 'Disconnected';

  final ecgLineData = <FlSpot>[];
  final ppgLineData = <FlSpot>[];
  final respLineData = <FlSpot>[];
  double ecgDataCounter = 0;
  double ppgDataCounter = 0;
  double respDataCounter = 0;

  int globalHeartRate = 0;
  int globalSpO2 = 0;
  int globalRespRate = 0;
  double globalTemp = 0;
  String displaySpO2 = "--";

  final int boardSamplingRate = 125;
  final int _plotWindowSeconds = 6;

  static const String _devicePath = '/dev/ttySAC0';
  static const int _baudRate = 3000000;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _framer = PacketFramer(
      onPacket: _onPacketReceived,
      onError: (_) {},
    );
    _decoder = decoderForBoard('Healthypi (USB)');

    _openPort();
  }

  Future<void> _openPort() async {
    await _stopRootReader();
    ecgLineData.clear();
    ppgLineData.clear();
    respLineData.clear();
    ecgDataCounter = 0;
    ppgDataCounter = 0;
    respDataCounter = 0;

    final hasRootAccess = await _ensureRootAccess();
    if (!hasRootAccess) {
        return;
    }

    final started = await _startRootReader();
    if (!started && mounted) {
      setState(() {
        _status = 'Failed to start UART reader on $_devicePath.';
      });
    }
  }

  Future<bool> _startRootReader() async {
    if (!(Platform.isAndroid || Platform.isLinux)) {
      return false;
    }

    try {
      await _runRootCommand(
        'stty -F $_devicePath $_baudRate raw -echo -onlcr -ocrnl -icrnl 2>/dev/null || true', //configure device for raw access
      );

      final process = await _startRootProcess('cat $_devicePath'); //launch root process to read device output
      if (process == null) {
        return false;
      }

      _rootReaderProcess = process;
      _rootStdoutSub = process.stdout.listen(
        _framer.processChunk,
        onDone: () {
          if (!mounted) return;
          setState(() {
            _status = 'UART reader stopped.';
          });
        },
      );
      _rootStderrSub = process.stderr
          .transform(utf8.decoder)
          .listen((e) {
        final errorText = e.trim();
        if (errorText.isEmpty) {
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _status = 'Root UART stderr: $errorText';
        });
      });

      if (!mounted) {
        return false;
      }

      setState(() {
        _status = 'Connected to $_devicePath';
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureRootAccess() async {
    if (!(Platform.isAndroid || Platform.isLinux)) {
      return true;
    }

    try {
      setState(() {
        _status = 'Requesting root access for $_devicePath...';
      });

      final result = await _runRootCommand(
        'test -e $_devicePath || exit 2',
      );

      if (result == null) {
        setState(() {
          _status =
              'Root shell (su) not found. Cannot access $_devicePath without root.';
        });
        return false;
      }

      if (result.exitCode != 0) {
        setState(() {
          final stderr = (result.stderr ?? '').toString().trim();
          _status =
              'Root command failed for $_devicePath (code ${result.exitCode}). ${stderr.isEmpty ? 'No stderr output.' : stderr}';
        });
        return false;
      }

      return true;
    } catch (e) {
      setState(() {
        _status = 'Root request failed: $e';
      });
      return false;
    }
  }

  Future<ProcessResult?> _runRootCommand(String command) async {
    const suCandidates = <String>[
      'su',
      '/system/xbin/su',
      '/system/bin/su',
    ];

    for (final suBinary in suCandidates) {
      try {
        final result = await Process.run(suBinary, ['-c', command]);
        return result;
      } catch (_) {
        // Try the next known su location.
      }
    }
    return null;
  }

  Future<Process?> _startRootProcess(String command) async {
    String suBinary = 'su';
    try {
      final process = await Process.start(suBinary, ['-c', command]);
      return process;
    } catch (e) {
      throw Exception('Failed to start root process with command "$command": $e');
    }
  }

  Future<void> _stopRootReader() async {
    await _rootStdoutSub?.cancel();
    await _rootStderrSub?.cancel();
    _rootStdoutSub = null;
    _rootStderrSub = null;
    _rootReaderProcess?.kill(ProcessSignal.sigterm);
    _rootReaderProcess = null;
  }

  void _onPacketReceived(FramedPacket packet) {
    final decoded = _decoder?.decode(packet);
    if (decoded == null) return;

    final windowSize = boardSamplingRate * _plotWindowSeconds.toDouble();
    _handleStandardData(decoded, windowSize);
  }

  void _handleStandardData(DecodedData decoded, double windowSize) {
    for (final sample in decoded.ecgSamples) {
      ecgLineData.add(FlSpot(ecgDataCounter++, sample));
    }
    for (final sample in decoded.respSamples) {
      respLineData.add(FlSpot(respDataCounter++, sample));
    }
    for (int i = 0; i < decoded.ppgSamples.length; i++) {
      if (decoded.ppgValidity != null && !decoded.ppgValidity![i]) continue;
      ppgLineData.add(FlSpot(ppgDataCounter++, decoded.ppgSamples[i]));
    }

    if (decoded.heartRate != null) globalHeartRate = decoded.heartRate!;
    if (decoded.respRate != null) globalRespRate = decoded.respRate!;
    if (decoded.spo2 != null) {
      globalSpO2 = decoded.spo2!;
      displaySpO2 = globalSpO2 == 25 ? '--' : '$globalSpO2 %';
    }
    if (decoded.temperature != null) globalTemp = decoded.temperature!;

    _manageDataWindow(ecgLineData, windowSize);
    _manageDataWindow(ppgLineData, windowSize);
    _manageDataWindow(respLineData, windowSize);
  }

  void _manageDataWindow(List<FlSpot> dataList, double windowSizeInSamples) {
    final bufferSize = windowSizeInSamples * 2.0;
    while (dataList.length > bufferSize) {
      dataList.removeAt(0);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    _stopRootReader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(title: const Text('UART Serial Display')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(_status),
          ),
          Expanded(
            child: GenericPlot(
              ecgDataBuilder: () => ecgLineData,
              spo2DataBuilder: () => ppgLineData,
              respDataBuilder: () => respLineData,
              samplingRate: boardSamplingRate,
              heartRateBuilder: () => globalHeartRate,
              spo2TextBuilder: () => displaySpO2,
              respRateBuilder: () => globalRespRate,
              temperatureBuilder: () => globalTemp,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openPort,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}