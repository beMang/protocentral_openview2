import 'SerialConnector.dart';
import 'package:usb_serial/usb_serial.dart';
import 'dart:async';
import 'dart:typed_data';

class SerialPhoneConnector extends SerialConnector{
  UsbPort? _port;
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<UsbEvent>? _usbEventSub;

  SerialPhoneConnector(Function(List<int>) onMessage, Function() onEvent) : super(onMessage, onEvent) {
    _listenUsbEvents();
  }

  void _listenUsbEvents() {
    _usbEventSub = UsbSerial.usbEventStream?.listen((event) {
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        usb_attached = true;
        onEvent();
        connect();
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        usb_attached = false;
        usb_connected = false;
        onEvent();
        disconnect();
      }
    });
  }

  @override
  Future<void> connect() async {
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
      onMessage(data);
    });

    _port = port;
    usb_connected = true;
    usb_attached = true;
    onEvent();
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await _port?.close();
    _sub = null;
    _port = null;
    usb_connected = false;
    usb_attached = false;
    onEvent();
  }

  dispose() {
    _usbEventSub?.cancel();
    super.dispose();
  }
}