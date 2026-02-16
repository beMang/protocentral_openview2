var listOFUSBBoards = {
  'Healthypi (USB)',
  'Healthypi 6 (USB)',
  'Sensything Ox (USB)',
  //'Healthypi EEG',
  'ADS1292R Breakout/Shield (USB)',
  'ADS1293 Breakout/Shield (USB)',
  'AFE4490 Breakout/Shield (USB)',
  'MAX86150 Breakout (USB)',
  'Pulse Express (USB)',
  'tinyGSR Breakout (USB)',
  'MAX30003 ECG Breakout (USB)',
  'MAX30001 ECG & BioZ Breakout (USB)'
};

var listOFBLEBoards = {
  'Healthypi (BLE)',
  'Sensything Ox (BLE)'
};

typedef LogHeader = ({
  int logFileID,
  int sessionLength,
  int fileNo,
  int tmSec,
  int tmMin,
  int tmHour,
  int tmMday,
  int tmMon,
  int tmYear
});
