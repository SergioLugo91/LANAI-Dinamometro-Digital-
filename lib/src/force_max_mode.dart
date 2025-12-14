import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database.dart';

enum Hand { left, right }

class ForceMaxModePage extends StatefulWidget {
  final int sessionId;
  final String sessionName;
  final BluetoothDevice connectedDevice;
  final BluetoothCharacteristic subscribedChar;
  final VoidCallback onTare;

  const ForceMaxModePage({
    super.key,
    required this.sessionId,
    required this.sessionName,
    required this.connectedDevice,
    required this.subscribedChar,
    required this.onTare,
  });

  @override
  State<ForceMaxModePage> createState() => _ForceMaxModePageState();
}

class _ForceMaxModePageState extends State<ForceMaxModePage> {
  StreamSubscription<List<int>>? _bleSub;

  Hand _activeHand = Hand.right;
  double _currentRight = 0.0;
  double _currentLeft = 0.0;
  double _maxRight = 0.0;
  double _maxLeft = 0.0;
  // Flags to temporarily hide the blue/current bar after a reset action
  final Map<Hand, bool> _hideBar = {Hand.right: false, Hand.left: false};

  @override
  void initState() {
    super.initState();
    // Activar notificaciones BLE y suscribirse a los datos
    widget.subscribedChar.setNotifyValue(true);
    _bleSub = widget.subscribedChar.lastValueStream.listen((bytes) {
      try {
        final s = String.fromCharCodes(bytes).trim();
        final parsed = double.tryParse(s);
        if (parsed != null) {
          _onData(parsed);
        }
      } catch (e) {
        // Ignorar errores de parseo de datos BLE
        // ignore: avoid_print
        print('Error parseando datos BLE: $e');
      }
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    widget.subscribedChar.setNotifyValue(false);
    super.dispose();
  }

  void _onData(double value) {
    setState(() {
      if (_activeHand == Hand.right) {
        _currentRight = value;
        // When new data arrives, ensure bar is visible again
        _hideBar[Hand.right] = false;
        if (value > _maxRight) {
          _maxRight = value;
        }
      } else {
        _currentLeft = value;
        _hideBar[Hand.left] = false;
        // When new data arrives, ensure bar is visible again
        if (value > _maxLeft) {
          _maxLeft = value;
        }
      }
    });
  }

  void _switchActive() {
    setState(() {
      _activeHand = _activeHand == Hand.right ? Hand.left : Hand.right;
    });
  }

  void _resetMax(Hand hand) {
    setState(() {
      if (hand == Hand.right) {
        _maxRight = 0.0;
        _currentRight = 0.0; // clear current visual
        _hideBar[Hand.right] = true; // temporarily hide the blue bar
      } else {
        _maxLeft = 0.0;
        _currentLeft = 0.0; // clear current visual
        _hideBar[Hand.left] = true; // temporarily hide the blue bar
      }
    });
    // Keep the bar hidden briefly to avoid immediate reappearance from incoming stream
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _hideBar[hand] = false;
      });
    });
  }

  // removed single-save method; use _saveBothMax to persist both maxima

  Widget _buildChart(String title, double current, double max) {
    // Using fl_chart LineChart to show current value and a horizontal max line
    // Draw a horizontal line at the current value (flat line across X axis)
    final spots = [FlSpot(0, current), FlSpot(1, current)];
    // Draw the current line unless explicitly hidden (allow showing at 0.00)
    final showCurrentBar = !_hideBar[ (title.contains('Derecha') ? Hand.right : Hand.left) ]!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(
              height: 150,
              child: Stack(
                children: [
                  LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 120,
                      // Always include at least one line to prevent mostRightSpot error
                      lineBarsData: [
                        if (showCurrentBar)
                          LineChartBarData(
                            spots: spots,
                            isCurved: false,
                            color: Colors.blue,
                            belowBarData: BarAreaData(show: true, color: const Color.fromRGBO(33,150,243,0.2)),
                            dotData: FlDotData(show: false),
                            barWidth: 6,
                          ),
                        // Always include an invisible line at zero to prevent empty chart errors
                        LineChartBarData(
                          spots: [FlSpot(0, 0), FlSpot(1, 0)],
                          isCurved: false,
                          color: Colors.transparent,
                          dotData: FlDotData(show: false),
                          barWidth: 0,
                        ),
                      ],
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: max, color: Colors.red, strokeWidth: 2, dashArray: [5, 5])]),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text('Actual: ${current.toStringAsFixed(1)} kg  Máx: ${max.toStringAsFixed(1)} kg'),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => _resetMax(title.contains('Derecha') ? Hand.right : Hand.left), child: const Text('Reset')),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _saveBothMax() async {
    final toSave = <Future>[];
    if (_maxRight > 0) toSave.add(DatabaseHelper.instance.saveMax(widget.sessionId, 'right', _maxRight));
    if (_maxLeft > 0) toSave.add(DatabaseHelper.instance.saveMax(widget.sessionId, 'left', _maxLeft));
    if (toSave.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay máximos para guardar')));
      return;
    }
    await Future.wait(toSave);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximos guardados')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo Fuerza Máxima'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  // Allow the session text to take available space and truncate if too long
                  Expanded(
                    child: Text(
                      'Sesión: ${widget.sessionName} (id ${widget.sessionId})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _switchActive, child: Text('Actualizar: ${_activeHand == Hand.right ? 'Mano Derecha' : 'Mano Izquierda'}')),
                ],
              ),
              const SizedBox(height: 12),
              // Two charts side by side on larger screens, stacked on small screens
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth > 700) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildChart('Mano Derecha', _currentRight, _maxRight)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildChart('Mano Izquierda', _currentLeft, _maxLeft)),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildChart('Mano Derecha', _currentRight, _maxRight),
                    _buildChart('Mano Izquierda', _currentLeft, _maxLeft),
                  ],
                );
              }),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: widget.onTare,
                    icon: const Icon(Icons.balance),
                    label: const Text('Tara'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: (_maxLeft <= 0 && _maxRight <= 0) ? null : _saveBothMax,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar máximos'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
