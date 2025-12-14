import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:typed_data';
import 'dart:async';


class RealtimeModePage extends StatefulWidget {
  final int sessionId;
  final String sessionName;
  final BluetoothDevice connectedDevice;
  final BluetoothCharacteristic subscribedChar;
  final VoidCallback onTare;

  const RealtimeModePage({
    super.key,
    required this.sessionId,
    required this.sessionName,
    required this.connectedDevice,
    required this.subscribedChar,
    required this.onTare,
  });

  @override
  State<RealtimeModePage> createState() => _RealtimeModePageState();
}

class _RealtimeModePageState extends State<RealtimeModePage> {
  final List<FlSpot> _dataPoints = [];
  final int _maxDataPoints = 100; // Límite de puntos en la gráfica
  double _xValue = 0;
  double _currentForce = 0.0;
  double _maxForce = 0.0;
  bool _isRunning = false;
  StreamSubscription<List<int>>? _bleSub;

  @override
  void initState() {
    super.initState();
    // Auto-iniciar en tiempo real (sin botón de iniciar)
    _start();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
    });
    widget.subscribedChar.setNotifyValue(true);
    _bleSub = widget.subscribedChar.lastValueStream.listen(_processIncomingData);
  }

  void _stop() async {
    await _bleSub?.cancel();
    _bleSub = null;
    try {
      await widget.subscribedChar.setNotifyValue(false);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _processIncomingData(List<int> data) {
    // Procesar los datos recibidos de la celda de carga
    // Esto depende del formato de datos de tu dispositivo
    double forceValue = _parseForceData(data);
    _currentForce = forceValue;
    
    // Actualizar el valor máximo para el eje Y dinámico
    if (forceValue > _maxForce) {
      _maxForce = forceValue;
    }
    
    setState(() {
      // Añadir nuevo punto de datos
      _dataPoints.add(FlSpot(_xValue, forceValue));
      _xValue += 1;
      
      // Limitar el número de puntos para evitar sobrecarga
      if (_dataPoints.length > _maxDataPoints) {
        _dataPoints.removeAt(0);
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



  void _clearData() {
    setState(() {
      _dataPoints.clear();
      _xValue = 0;
      _maxForce = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos en Tiempo Real'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearData,
            tooltip: 'Limpiar gráfica',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Sesión: ${widget.sessionName}'),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: _maxForce + 10 < 30 ? 30 : _maxForce + 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _dataPoints,
                      isCurved: true,
                      color: Colors.purple,
                      dotData: FlDotData(show: false),
                      barWidth: 2,
                    ),
                  ],
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 10,
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
            ),

            const SizedBox(height: 12),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                child: Column(
                  children: [
                    const Text('Valor Actual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      '${_currentForce.toStringAsFixed(2)} kg',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.onTare,
                  icon: const Icon(Icons.balance),
                  label: const Text('Tara'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}