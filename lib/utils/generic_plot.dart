import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../globals.dart';
import 'charts.dart';

class GenericPlot extends StatefulWidget {
  const GenericPlot(
      {super.key,
      required this.ecgDataBuilder,
      required this.spo2DataBuilder,
      required this.respDataBuilder,
      required this.samplingRate,
  required this.heartRateBuilder,
  required this.spo2TextBuilder,
  required this.respRateBuilder,
  required this.temperatureBuilder,
      this.ecgColor = Colors.green,
      this.spo2Color = Colors.yellow,
      this.respColor = Colors.blue});

  final List<FlSpot> Function() ecgDataBuilder;
  final List<FlSpot> Function() spo2DataBuilder;
  final List<FlSpot> Function() respDataBuilder;
  final int samplingRate;

  final int Function() heartRateBuilder;
  final String Function() spo2TextBuilder;
  final int Function() respRateBuilder;
  final double Function() temperatureBuilder;

  final Color ecgColor;
  final Color spo2Color;
  final Color respColor;

  @override
  State<GenericPlot> createState() => _GenericPlotState();
}

class _GenericPlotState extends State<GenericPlot> {
  static const List<int> _windowSizeOptions = [3, 6, 9, 12];
  static const List<int> _refreshRateOptions = [2, 5, 10, 20];

  int _plotWindowSeconds = 6;
  int _refreshRateHz = 5;
  Timer? _refreshTimer;

  static const double _chartSectionHeight = 120;
  static const int _chartPlotHeight = 10;

  @override
  void initState() {
    super.initState();
    _restartRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _restartRefreshTimer() {
    _refreshTimer?.cancel();
    final refreshInterval =
        Duration(milliseconds: (1000 / _refreshRateHz).round());
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  List<double> _getCurrentXAxisRange(List<FlSpot> data) {
    final windowSizeInSamples =
        _plotWindowSeconds.toDouble() * widget.samplingRate;
    if (data.isEmpty) {
      return [0, windowSizeInSamples];
    }

    final maxX = data.last.x;
    var minX = maxX - windowSizeInSamples;

    if (minX < 0) {
      minX = 0;
    }

    return [minX, maxX < windowSizeInSamples ? windowSizeInSamples : maxX];
  }

  List<FlSpot> _getWindowedData(List<FlSpot> fullData) {
    if (fullData.isEmpty) return const [];

    final range = _getCurrentXAxisRange(fullData);
    final minX = range[0];
    final maxX = range[1];

    return fullData
        .where((point) => point.x >= minX && point.x <= maxX)
        .toList(growable: false);
  }

  Widget _buildStreamingChart(int height, List<FlSpot> source, Color color) {
    final refreshKey = source.isEmpty
        ? 'empty-$height-${color.value}'
        : '${source.length}-${source.last.x}-${source.last.y}';

    if (source.isEmpty) {
      return RepaintBoundary(
        key: ValueKey<String>(refreshKey),
        child: buildPlots().buildChart(height, 95, const [], color),
      );
    }

    final windowedData = _getWindowedData(source);
    final xAxisRange = _getCurrentXAxisRange(source);
    return RepaintBoundary(
      key: ValueKey<String>(refreshKey),
      child: buildPlots().buildChartWithRange(
        height,
        95,
        windowedData,
        color,
        xAxisRange[0],
        xAxisRange[1],
      ),
    );
  }

  Widget _buildMetric(String title, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(String title, List<FlSpot> data, Color color, [int height = 20]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        Expanded(
          child: _buildStreamingChart(height, data, color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ecgData = List<FlSpot>.of(widget.ecgDataBuilder(), growable: false);
    final spo2Data = List<FlSpot>.of(widget.spo2DataBuilder(), growable: false);
    final respData = List<FlSpot>.of(widget.respDataBuilder(), growable: false);

    final heartRate = widget.heartRateBuilder();
    final spo2Text = widget.spo2TextBuilder();
    final respRate = widget.respRateBuilder();
    final temperature = widget.temperatureBuilder();

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Container(
            color: Colors.black,
            padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: Row(
                children: [
                const Text(
                  'Window: ',
                  style: TextStyle(fontSize: 10.0, color: Colors.white),
                ),
                DropdownButton<int>(
                  dropdownColor: hPi4Global.hpi4Color,
                  value: _plotWindowSeconds,
                  style: const TextStyle(color: Colors.white, fontSize: 10.0),
                  underline: Container(height: 1, color: Colors.white),
                  items: _windowSizeOptions
                    .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value secs',
                        style: const TextStyle(color: Colors.white)),
                    ),
                    )
                    .toList(),
                  onChanged: (newValue) {
                  if (newValue == null) return;
                  setState(() {
                    _plotWindowSeconds = newValue;
                  });
                  },
                ),
                const SizedBox(width: 24),
                const Text(
                  'Refresh: ',
                  style: TextStyle(fontSize: 10.0, color: Colors.white),
                ),
                DropdownButton<int>(
                  dropdownColor: hPi4Global.hpi4Color,
                  value: _refreshRateHz,
                  style: const TextStyle(color: Colors.white, fontSize: 10.0),
                  underline: Container(height: 1, color: Colors.white),
                  items: _refreshRateOptions
                    .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value Hz',
                        style: const TextStyle(color: Colors.white)),
                    ),
                    )
                    .toList(),
                  onChanged: (newValue) {
                  if (newValue == null) return;
                  setState(() {
                    _refreshRateHz = newValue;
                  });
                  _restartRefreshTimer();
                  },
                ),
                Expanded(
                  child: Container(
                  color: Colors.grey[900],
                  padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Row(
                    children: [
                    _buildMetric('BPM', '$heartRate bpm'),
                    _buildMetric('SPO2', spo2Text),
                    _buildMetric('RPM', '$respRate rpm'),
                    _buildMetric('TEMP',
                      '${temperature.toStringAsPrecision(3)}° C'),
                    ],
                  ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  //to support different display in function of device, replace this row creation with a function that do a switch case on selectedBoard.
                  children: [
                    SizedBox(
                      height: _chartSectionHeight,
                      child: _buildChartSection('ECG', ecgData, widget.ecgColor, _chartPlotHeight),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: _chartSectionHeight,
                      child: _buildChartSection('SPO2', spo2Data, widget.spo2Color, _chartPlotHeight),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: _chartSectionHeight,
                      child: _buildChartSection('RESP', respData, widget.respColor, _chartPlotHeight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
