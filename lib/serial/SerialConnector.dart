abstract class SerialConnector {
  final Function(List<int>) _onMessage;
  final Function() _onEvent;

  bool usb_attached = false;
  bool usb_connected = false;

  SerialConnector(Function(List<int>) onMessage, Function() onEvent)      : _onMessage = onMessage, _onEvent = onEvent;

  void Function(List<int>) get onMessage => _onMessage;
  void Function() get onEvent => _onEvent;

  Future<void> connect(); //callback in arg
  Future<void> disconnect();
  void dispose() {
    disconnect();
  }
}