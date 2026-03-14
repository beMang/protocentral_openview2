import 'SerialConnector.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'dart:async';

class SerialDesktopConnector extends SerialConnector{
  final SerialPort _port;
  final String selectedPort;

  SerialDesktopConnector(Function(List<int>) onMessage, Function() onEvent, String selectedPort)
      : _port = SerialPort(selectedPort),
        selectedPort = selectedPort,
        super(onMessage, onEvent);

  Future<void> connect() async {
    if (selectedPort.isEmpty || selectedPort == 'null') {
      throw SerialPortError('No serial port selected');
    }
    // Check if port is open, if not, try to open it
    if (!_port.isOpen) {
      if (!_port.openReadWrite()) {
        throw SerialPortError('Device not configured : $selectedPort');
      }
    }

    // Configure the port parameters
    final config = SerialPortConfig();
    config.baudRate = 115200;
    config.bits = 8;
    config.stopBits = 1;
    config.parity = SerialPortParity.none;
    config.setFlowControl(SerialPortFlowControl.none);
    _port.config = config;

    final serialStream = SerialPortReader(_port);
    serialStream.stream.listen(
      (data) {
        onMessage(data);
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
    usb_attached = true;
    usb_connected = true;
    onEvent();
  }

  Future<void> disconnect() async {
    if (_port.isOpen) {
      _port.close();
    }
    usb_attached = false;
    usb_connected = false;
    onEvent();
  }
}