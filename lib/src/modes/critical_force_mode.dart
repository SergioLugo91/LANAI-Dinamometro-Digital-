import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../database.dart';

class CriticalForceModePage extends StatefulWidget {
  final int sessionId;
  final String sessionName;
  final BluetoothDevice connectedDevice;
  final BluetoothCharacteristic subscribedChar;
  final VoidCallback onTare;

  const CriticalForceModePage({
    super.key,
    required this.sessionId,
    required this.sessionName,
    required this.connectedDevice,
    required this.subscribedChar,
    required this.onTare,
  });

  @override
  State<CriticalForceModePage> createState() => _CriticalForceModePageState();
}


class _CriticalForceModePageState extends State<CriticalForceModePage> {
  static const int totalPulls = 24;
  static const int pullDuration = 7; // seconds
  static const int restDuration = 3; // seconds

  int _currentPull = 1;
  int _secondsLeft = pullDuration;
  bool _isRunning = false;
  bool _isRest = false;
  double _criticalForce = 0.0;
  List<List<double>> _pullsData = [];
  List<double> _pullMeans = [];
  List<FlSpot> _dataPoints = [];
  List<double> _currentPullData = [];
  int _nextSpotX = 0;
  List<Map<String, dynamic>> _pullRanges = []; // {start,end,mean}
  int? _currentPullStartX;
  bool _completed = false;
  bool _saved = false;
  Timer? _timer;
  StreamSubscription<List<int>>? _bleSub;

  @override
  void initState() {
    super.initState();
    // Activar notificaciones BLE
    widget.subscribedChar.setNotifyValue(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isRunning && _bleSub != null) _bleSub!.cancel();
    widget.subscribedChar.setNotifyValue(false);
    super.dispose();
  }

  void _startTest() {
    setState(() {
      _isRunning = true;
      _isRest = false;
      _currentPull = 1;
      _secondsLeft = pullDuration;
      _pullsData.clear();
      _pullMeans.clear();
      _criticalForce = 0;
      _dataPoints.clear();
      _currentPullData.clear();
      _nextSpotX = 0;
      _pullRanges.clear();
      _currentPullStartX = 0;
      _completed = false;
      _saved = false;
    });
    // Asegurar que las notificaciones BLE estén activas
    widget.subscribedChar.setNotifyValue(true);
    _bleSub = widget.subscribedChar.lastValueStream.listen(_onBLEData);
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuerza Crítica'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Sesión: ${widget.sessionName}'),
            const SizedBox(height: 8),
            // ...session header (card moved below the chart)
            const SizedBox(height: 8),
            if (_isRunning)
              Column(
                children: [
                  Text(_isRest ? 'Descanso' : 'Jalón ${_currentPull > totalPulls ? totalPulls : _currentPull} de $totalPulls',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Tiempo restante: $_secondsLeft s'),
                  const SizedBox(height: 8),
                ],
              ),
            // Chart with fixed, smaller height
            SizedBox(
              height: 240,
              child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 120,
                    lineBarsData: [
                      // main data series
                      LineChartBarData(
                        spots: _dataPoints,
                        isCurved: true,
                        color: Colors.purple,
                        dotData: FlDotData(show: false),
                        barWidth: 2,
                      ),
                      // per-pull mean segments
                      ..._pullRanges.map((r) {
                        final s = r['start'] as int;
                        final e = r['end'] as int;
                        final m = (r['mean'] as num).toDouble();
                        if (e < s) return LineChartBarData(spots: []);
                        return LineChartBarData(
                          spots: [FlSpot(s.toDouble(), m), FlSpot(e.toDouble(), m)],
                          isCurved: false,
                          color: Colors.orange.withOpacity(0.9),
                          dotData: FlDotData(show: false),
                          barWidth: 2,
                        );
                      }).toList(),
                    ],
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 50,
                        getTitlesWidget: (value, meta) {
                          const style = TextStyle(fontSize: 10);
                          // show integer labels only for multiples of 5
                          if (value % 5 == 0) return Text(value.toInt().toString(), style: style);
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: 10,
                        getTitlesWidget: (value, meta) {
                          return Text(value.toInt().toString(), style: const TextStyle(fontSize: 12));
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineTouchData: LineTouchData(enabled: true),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: _criticalForce > 0 && _completed
                        ? [HorizontalLine(y: _criticalForce, color: Colors.tealAccent, strokeWidth: 2, dashArray: [6, 3])]
                        : [],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Moved: Card with estimated critical force (larger and below chart)
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                child: Column(
                  children: [
                    const Text('Fuerza Crítica Estimada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      '${_criticalForce.toStringAsFixed(2)} kg',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _startTest,
                  child: const Text('Iniciar'),
                ),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : widget.onTare,
                  icon: const Icon(Icons.balance),
                  label: const Text('Tara'),
                ),
                if (_isRunning)
                  ElevatedButton(
                    onPressed: () {
                      _timer?.cancel();
                      _bleSub?.cancel();
                      setState(() {
                        _isRunning = false;
                      });
                    },
                    child: const Text('Detener'),
                  ),
                if (_completed && !_saved)
                  ElevatedButton(
                    onPressed: () async {
                      await DatabaseHelper.instance.saveCriticalForce(widget.sessionId, _criticalForce);
                      setState(() {
                        _saved = true;
                      });
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fuerza crítica guardada: ${_criticalForce.toStringAsFixed(2)} kg')));
                    },
                    child: const Text('Guardar resultado'),
                  ),
              ],
            ),
            if (_pullMeans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Fuerza media última repetición: ${_pullMeans.last.toStringAsFixed(2)} kg'),
              ),
          ],
        ),
      ),
    );
  }
  void _tick(Timer timer) {
    setState(() {
      _secondsLeft--;
      if (_secondsLeft <= 0) {
        if (!_isRest) {
          // End of pull, calculate mean
          double mean = _currentPullData.isNotEmpty
              ? _currentPullData.reduce((a, b) => a + b) / _currentPullData.length
              : 0.0;
          // record end index for this pull
          final endIdx = _nextSpotX - 1;
          final startIdx = _currentPullStartX ?? 0;
          _pullMeans.add(mean);
          _pullsData.add(List.from(_currentPullData));
          _pullRanges.add({'start': startIdx, 'end': endIdx, 'mean': mean});
          _currentPullData.clear();
          _isRest = true;
          _secondsLeft = restDuration;
        } else {
          // End of rest, next pull or finish
          _isRest = false;
          _currentPull++;
          // next pull starts at current nextSpotX
          _currentPullStartX = _nextSpotX;
          _secondsLeft = pullDuration;
          if (_currentPull > totalPulls) {
            _finishTest();
          }
        }
      }
    });
  }

  double _parseForceData(List<int> data) {
    // Primero intenta interpretar como cadena ASCII (UART TX envía "0.00")
    try {
      final s = String.fromCharCodes(data).trim();
      final v = double.tryParse(s);
      if (v != null) return v;
    } catch (_) {}

    // Fallbacks binarios en caso de que el dispositivo envíe binario
    if (data.length >= 4) {
      var byteData = ByteData.sublistView(Uint8List.fromList(data));
      return byteData.getFloat32(0, Endian.little);
    } else if (data.length >= 2) {
      return (data[0] + (data[1] << 8)).toDouble();
    }

    return 0.0;
  }

  void _onBLEData(List<int> data) {
    double force = _parseForceData(data);
    if (_isRunning && _currentPull <= totalPulls) {
      // Always update chart so the graph stays live during rest. Only
      // accumulate samples into the current pull while not resting.
      if (!_isRest) {
        _currentPullData.add(force);
      }
      setState(() {
        _dataPoints.add(FlSpot(_nextSpotX.toDouble(), force));
        _nextSpotX++;
      });
    }
  }
  void _finishTest() async {
    _timer?.cancel();
    if (_bleSub != null) await _bleSub!.cancel();
    setState(() {
      _isRunning = false;
    });
    // Calcular fuerza crítica: media de las últimas 6 repeticiones
    if (_pullMeans.length >= 6) {
      final last6 = _pullMeans.sublist(_pullMeans.length - 6);
      _criticalForce = last6.reduce((a, b) => a + b) / last6.length;
      setState(() {
        _completed = true;
      });
      // now wait for user to press the save button to persist the value
    }
  }
}
