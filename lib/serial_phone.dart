import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:usb_serial/usb_serial.dart';

import 'home.dart';
import 'generic_plot.dart';
import 'globals.dart';
import 'utils/sizeConfig.dart';
import 'ble/ble_scanner.dart';
import 'utils/logDataToFile.dart';
import 'states/OpenViewBLEProvider.dart';
import 'package:flutter/src/foundation/change_notifier.dart';
import 'protocol/protocol.dart';

class SerialPhonePage extends StatefulWidget {
  const SerialPhonePage() : super();

  @override
  _SerialPhonePageState createState() => _SerialPhonePageState();
}

class _SerialPhonePageState extends State<SerialPhonePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  Key key = UniqueKey();

  late final PacketFramer _framer;
  late final BoardDecoder? _decoder;

  UsbPort? _port;
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<UsbEvent>? _usbEventSub;
  bool usb_attached = false;
  bool usb_connected = false;

  final ecgLineData = <FlSpot>[];
  final ppgLineData = <FlSpot>[];
  final respLineData = <FlSpot>[];

  List<double> ecgDataLog = [];
  List<double> ppgDataLog = [];
  List<double> respDataLog = [];

  double ecgDataCounter = 0;
  double ppgDataCounter = 0;
  double respDataCounter = 0;

  double ecg1DataCounter = 0;
  double ecg2DataCounter = 0;

  final ValueNotifier<List<FlSpot>> ecgLineData1 = ValueNotifier([]);
  final ValueNotifier<List<FlSpot>> ppgLineData1 = ValueNotifier([]);
  final ValueNotifier<List<FlSpot>> respLineData1 = ValueNotifier([]);

  bool startDataLogging = false;
  bool startEEGStreaming = false;

  int globalHeartRate = 0;
  int globalSpO2 = 0;
  int globalRespRate = 0;
  double globalTemp = 0;
  String displaySpO2 = "--";

  /// Configurable window size in seconds for plotting
  static const List<int> _windowSizeOptions = [3, 6, 9, 12];
  int _plotWindowSeconds = 6; // Default value

  @override
  void initState() {
    super.initState();

    _framer = PacketFramer(
      onPacket: _onPacketReceived,
      onError: (_) {},
    );
    _decoder = decoderForBoard('Healthypi (USB)');

    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _listenUsbEvents();
    _connect().catchError((e) {
      _showSerialPortErrorDialog(
          "Failed to connect to the serial device. Please ensure it's properly connected and try again.\n\nError details: $e");
    });
  }

  @override
  dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    ecgLineData.clear();
    ppgLineData.clear();
    respLineData.clear();

    _usbEventSub?.cancel();
    _disconnect();

    super.dispose();
  }

  void _listenUsbEvents() {
    _usbEventSub = UsbSerial.usbEventStream?.listen((event) {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        usb_attached = true;
        _connect().catchError((e) {
          _showSerialPortErrorDialog(
              "Failed to connect to the serial device. Please ensure it's properly connected and try again.\n\nError details: $e");
        }); // Attempt to connect when a device is attached
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        usb_attached = false;
        usb_connected = false;
        _disconnect();
      }
      setState(() {});
    });
  }

  Future<void> _connect() async {
    if (_port != null) return;

    final devices = await UsbSerial.listDevices();
    if (devices.isEmpty) return;

    final device = devices.first;
    final port = await device.create();
    if (port == null) return;

    if (!await port.open()) return;

    await port.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _sub = port.inputStream!.listen((data) {
      _framer.processChunk(data);
    });

    _port = port;
    usb_connected = true;
    usb_attached = true;

    setState(() {});
  }

  Future<void> _disconnect() async {
    await _sub?.cancel();
    await _port?.close();
    _sub = null;
    _port = null;
    usb_connected = false;
    usb_attached = false;

    setState(() {});
  }

  // Add this helper to show a dialog for serial port errors
  void _showSerialPortErrorDialog(String errorMsg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Serial Port Error'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Icon(
                  Icons.error,
                  color: Colors.red,
                  size: 72,
                ),
                Center(
                  child: Column(children: <Widget>[
                    Text(
                      errorMsg,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Ok'),
              onPressed: () async {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => HomePage(title: 'OpenView')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Helper method to manage data window size for regular List<FlSpot>
  /// Keep enough data for smooth scrolling but not excessive memory usage
  void _manageDataWindow(List<FlSpot> dataList, double windowSizeInSamples) {
    // Keep 2x the window size to ensure smooth scrolling and avoid gaps
    double bufferSize = windowSizeInSamples * 2.0;
    while (dataList.length > bufferSize) {
      dataList.removeAt(0);
    }
  }

  /// Updated toolbar with proper window size change handling
  Widget buildToolbar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Window: ",
                style: TextStyle(fontSize: 14.0, color: Colors.white),
              ),
              DropdownButton<int>(
                dropdownColor: hPi4Global.hpi4Color,
                value: _plotWindowSeconds,
                style: const TextStyle(color: Colors.white, fontSize: 14.0),
                underline: Container(height: 1, color: Colors.white),
                items: _windowSizeOptions.map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text("$value secs",
                        style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _plotWindowSeconds = newValue!;
                    // No need to reset scrolling - it will automatically adjust
                  });
                },
              ),
            ],
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  void _onPacketReceived(FramedPacket packet) {
    final decoded = _decoder?.decode(packet);
    if (decoded == null) return;

    final windowSize = boardSamplingRate * _plotWindowSeconds.toDouble();
    _handleStandardData(decoded, windowSize);
  }

  void _handleStandardData(DecodedData decoded, double windowSize) {
    // Accumulate data without triggering a rebuild on every packet.
    for (final sample in decoded.ecgSamples) {
      ecgLineData.add(FlSpot(ecgDataCounter++, sample));
    }
    for (final sample in decoded.respSamples) {
      respLineData.add(FlSpot(respDataCounter++, sample));
    }
    for (int i = 0; i < decoded.ppgSamples.length; i++) {
      // For MAX30001, only add PPG when valid
      if (decoded.ppgValidity != null && !decoded.ppgValidity![i]) continue;
      ppgLineData.add(FlSpot(ppgDataCounter++, decoded.ppgSamples[i]));
    }

    if (startDataLogging) {
      final ecgLog = decoded.ecgLogSamples ?? decoded.ecgSamples;
      final ppgLog = decoded.ppgLogSamples ?? decoded.ppgSamples;
      final respLog = decoded.respLogSamples ?? decoded.respSamples;
      ecgDataLog.addAll(ecgLog);
      ppgDataLog.addAll(ppgLog);
      respDataLog.addAll(respLog);
    }

    if (decoded.heartRate != null) globalHeartRate = decoded.heartRate!;
    if (decoded.respRate != null) globalRespRate = decoded.respRate!;
    if (decoded.spo2 != null) {
      globalSpO2 = decoded.spo2!;
      displaySpO2 = globalSpO2 == 25 ? "--" : "$globalSpO2 %";
    }
    if (decoded.temperature != null) globalTemp = decoded.temperature!;

    _manageDataWindow(ecgLineData, windowSize);
    _manageDataWindow(ppgLineData, windowSize);
    _manageDataWindow(respLineData, windowSize);
  }

  Widget sizedBoxForCharts() {
    return SizedBox(
      height: SizeConfig.blockSizeVertical * 1,
    );
  }

  Widget displayDeviceName() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "${usb_attached ? (usb_connected ? "Connected to HP5" : "Serial device attached") : "No Serial Device"}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  String debugText = "Console Inited...";

  Widget displayDisconnectButton() {
    return Consumer3<BleScannerState, BleScanner, OpenViewBLEProvider>(
        builder: (context, bleScannerState, bleScanner, wiserBle, child) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: MaterialButton(
              minWidth: 100.0,
              color: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              onPressed: () async {
                if (usb_connected) {
                  await _disconnect();
                }
                if (startDataLogging == true) {
                  startDataLogging = false;
                  startEEGStreaming = false;
                  writeLogDataToFile(ecgDataLog, ppgDataLog, respDataLog, context);
                } else {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => HomePage(title: 'OpenView')),
                  );
                }
              },
              child: const Row(
                children: <Widget>[
                  Text('Stop',
                      style: TextStyle(fontSize: 18.0, color: Colors.white)),
                ],
              ),
            ),
          );
        });
  }

  /// Returns the sampling rate based on the selected board.
  int boardSamplingRate = 128;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset('assets/ucl_logo.png',
                fit: BoxFit.fitWidth, height: 30),
            SizedBox(
              width: SizeConfig.blockSizeHorizontal * 5,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: MaterialButton(
                minWidth: 80.0,
                color: startDataLogging ? Colors.grey : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                onPressed: () async {
                  setState(() {
                    startDataLogging = true;
                  });
                },
                child: const Row(
                  children: <Widget>[
                    Text('Start Logging',
                        style: TextStyle(
                            fontSize: 16.0, color: hPi4Global.hpi4Color)),
                  ],
                ),
              ),
            ),
            // --- Window size dropdown removed from here ---
            displayDeviceName(),
            displayDisconnectButton(),
          ],
        ),
      ),
      body: Center(
        child: Container(
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
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
          ),
        ),
      ),
    );
  }
}