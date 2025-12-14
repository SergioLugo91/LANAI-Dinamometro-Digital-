import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import '../database.dart';

enum Hand { left, right }

class ExplosiveForceModePage extends StatefulWidget {
  final int sessionId;
  final String sessionName;
  final BluetoothDevice connectedDevice;
  final BluetoothCharacteristic subscribedChar;
  final VoidCallback onTare;

  const ExplosiveForceModePage({
    super.key,
    required this.sessionId,
    required this.sessionName,
    required this.connectedDevice,
    required this.subscribedChar,
    required this.onTare,
  });

  @override
  State<ExplosiveForceModePage> createState() => _ExplosiveForceModePageState();
}

class _ExplosiveForceModePageState extends State<ExplosiveForceModePage> {
  Hand _activeHand = Hand.right;
  final Map<Hand, List<FlSpot>> _dataPoints = {Hand.right: [], Hand.left: []};
  final Map<Hand, double> _maxForce = {Hand.right: 0.0, Hand.left: 0.0};
  final Map<Hand, double> _rateOfForce = {Hand.right: 0.0, Hand.left: 0.0};
  final Map<Hand, bool> _completed = {Hand.right: false, Hand.left: false};
  final Map<Hand, bool> _saved = {Hand.right: false, Hand.left: false};

  bool _isRunning = false;
  double _currentForce = 0.0;
  double _xValue = 0.0;
  StreamSubscription<List<int>>? _bleSub;
  Timer? _checkStopTimer;

  @override
  void initState() {
    super.initState();
    widget.subscribedChar.setNotifyValue(true);
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _checkStopTimer?.cancel();
    widget.subscribedChar.setNotifyValue(false);
    super.dispose();
  }

  void _startMeasurement() {
    if (_isRunning) return;
    
    setState(() {
      _isRunning = true;
      _dataPoints[_activeHand]!.clear();
      _maxForce[_activeHand] = 0.0;
      _rateOfForce[_activeHand] = 0.0;
      _completed[_activeHand] = false;
      _saved[_activeHand] = false;
      _xValue = 0.0;
    });

    _bleSub = widget.subscribedChar.lastValueStream.listen((bytes) {
      try {
        final s = String.fromCharCodes(bytes).trim();
        final parsed = double.tryParse(s);
        if (parsed != null) {
          _onData(parsed);
        }
      } catch (_) {}
    });

    // Verificar cada 100ms si los valores bajaron por debajo del 20% del máximo
    _checkStopTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isRunning && _maxForce[_activeHand]! > 0 && _currentForce < _maxForce[_activeHand]! * 0.2) {
        _stopMeasurement();
      }
    });
  }

  void _stopMeasurement() {
    if (!_isRunning) return;

    _checkStopTimer?.cancel();
    _bleSub?.cancel();

    setState(() {
      _isRunning = false;
    });

    _calculateRateOfForce();
  }

  void _onData(double value) {
    _currentForce = value;

    setState(() {
      _dataPoints[_activeHand]!.add(FlSpot(_xValue, value));
      _xValue += 1;

      if (value > _maxForce[_activeHand]!) {
        _maxForce[_activeHand] = value;
      }
    });
  }

  void _calculateRateOfForce() {
    final points = _dataPoints[_activeHand]!;
    if (points.isEmpty) return;

    final max = _maxForce[_activeHand]!;
    final threshold20 = max * 0.2;
    final threshold80 = max * 0.8;

    double? point20X, point20Y, point80X, point80Y;

    // Buscar puntos en los umbrales
    for (var p in points) {
      if (p.y >= threshold20 && point20X == null) {
        point20X = p.x;
        point20Y = p.y;
      }
      if (p.y >= threshold80 && point80X == null) {
        point80X = p.x;
        point80Y = p.y;
      }
    }

    if (point20X != null && point80X != null && point80X > point20X) {
      // Calcular pendiente: (y2 - y1) / (x2 - x1)
      // Asumir que cada punto es 1 muestra
      final pendiente = (point80Y! - point20Y!) / (point80X - point20X);
      setState(() {
        _rateOfForce[_activeHand] = pendiente;
        _completed[_activeHand] = true;
      });
    }
  }

  void _switchActive() {
    setState(() {
      _activeHand = _activeHand == Hand.right ? Hand.left : Hand.right;
    });
  }

  void _clearData() {
    setState(() {
      _dataPoints[_activeHand]!.clear();
      _maxForce[_activeHand] = 0.0;
      _rateOfForce[_activeHand] = 0.0;
      _completed[_activeHand] = false;
      _saved[_activeHand] = false;
      _xValue = 0.0;
    });
  }

  Future<void> _saveBothHands() async {
    final toSave = <Future>[];
    if (_completed[Hand.right]! && !_saved[Hand.right]!) {
      toSave.add(DatabaseHelper.instance.saveExplosiveForce(
        widget.sessionId,
        'right',
        _rateOfForce[Hand.right]!,
        _maxForce[Hand.right]!,
      ));
    }
    if (_completed[Hand.left]! && !_saved[Hand.left]!) {
      toSave.add(DatabaseHelper.instance.saveExplosiveForce(
        widget.sessionId,
        'left',
        _rateOfForce[Hand.left]!,
        _maxForce[Hand.left]!,
      ));
    }

    if (toSave.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa ambas manos antes de guardar')),
      );
      return;
    }

    await Future.wait(toSave);
    setState(() {
      _saved[Hand.right] = true;
      _saved[Hand.left] = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos de fuerza explosiva guardados')),
    );
  }

  Widget _buildChart() {
    final points = _dataPoints[_activeHand]!;
    final max = _maxForce[_activeHand]!;

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: max + 10 < 30 ? 30 : max + 10,
          lineBarsData: [
            LineChartBarData(
              spots: points.isNotEmpty ? points : [FlSpot(0, 0)],
              isCurved: true,
              color: Colors.red,
              dotData: FlDotData(show: false),
              barWidth: 2,
            ),
            // Línea invisible para evitar errores de fl_chart
            LineChartBarData(
              spots: [FlSpot(0, 0), FlSpot(1, 0)],
              isCurved: false,
              color: Colors.transparent,
              dotData: FlDotData(show: false),
              barWidth: 0,
            ),
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
                  if (value % 5 == 0) return Text(value.toInt().toString(), style: style);
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 20,
                getTitlesWidget: (value, meta) {
                  return Text(value.toInt().toString());
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(enabled: true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuerza Explosiva'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sesión: ${widget.sessionName} (id ${widget.sessionId})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _switchActive,
                    child: Text('Mano: ${_activeHand == Hand.right ? 'Derecha' : 'Izquierda'}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildChart(),
              const SizedBox(height: 12),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                  child: Column(
                    children: [
                      const Text('Tasa de Desarrollo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        '${_rateOfForce[_activeHand]!.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Máximo: ${_maxForce[_activeHand]!.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text('Mano Derecha', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        _completed[Hand.right]! ? '${_rateOfForce[Hand.right]!.toStringAsFixed(2)}' : '--',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Mano Izquierda', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        _completed[Hand.left]! ? '${_rateOfForce[Hand.left]!.toStringAsFixed(2)}' : '--',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _isRunning ? _stopMeasurement : (_completed[_activeHand]! ? _clearData : _startMeasurement),
                    child: Text(_isRunning ? 'Detener' : (_completed[_activeHand]! ? 'Nueva Medición' : 'Iniciar')),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: widget.onTare,
                    icon: const Icon(Icons.balance),
                    label: const Text('Tara'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: (_completed[Hand.right]! && _completed[Hand.left]!) ? _saveBothHands : null,
                icon: const Icon(Icons.save),
                label: const Text('Guardar ambas manos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}