import 'package:flutter/material.dart';
import 'src/database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/force_max_mode.dart';
import 'src/history_page.dart';
import 'src/modes/realtime_mode.dart';
import 'src/modes/explosive_force_mode.dart';
import 'src/modes/critical_force_mode.dart';
import 'src/widgets/mode_card.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Función principal:  punto de entrada de la app Flutter
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Solicitar permisos de Bluetooth
  await _requestBluetoothPermissions();

  // Cerrar sesiones que hayan quedado abiertas
  try {
    final sessions = await DatabaseHelper.instance.getAllSessions();
    for (var s in sessions) {
      final active = (s['active'] ??  0) as int;
      if (active == 1) {
        final id = s['id'] as int;
        await DatabaseHelper.instance. closeSession(id);
      }
    }
  } catch (e) {
    print('Error cerrando sesiones al inicio: $e');
  }

  runApp(const MyApp());
}

// Solicitar permisos necesarios para Bluetooth
Future<void> _requestBluetoothPermissions() async {
  final permissions = [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission. location,
  ];

  for (var permission in permissions) {
    final status = await permission.request();
    print('Permiso $permission: $status');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dinamómetro Digital',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors. deepPurple),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme. fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F1B2E)),
        textTheme: ThemeData.dark().textTheme,
      ),
      home: const MyHomePage(title: 'Inicio'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _nameController = TextEditingController();

  // Perfiles y sesiones
  List<Map<String, dynamic>> _profiles = [];
  int?  _selectedProfileId;
  bool _creatingNew = false;
  String _savedName = '';
  int?  _sessionId;
  DateTime?  _sessionStart;

  // BLE variables
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _subscribedChar; // TX (Notify) - recibe datos
  BluetoothCharacteristic? _rxChar; // RX (Write) - envía comandos
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];

  @override
  void dispose() {
    _closeSessionOnExit();
    _disconnectBLE();
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _listenBluetoothState();
  }

  // ================== FUNCIONES BLE MEJORADAS ==================

  /// Escuchar el estado del adaptador Bluetooth
  void _listenBluetoothState() {
    FlutterBluePlus. adapterState.listen((state) {
      if (mounted && state != BluetoothAdapterState. on) {
        _disconnectBLE();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth desactivado'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  /// Escanear dispositivos BLE cercanos
  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      // Iniciar escaneo
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      // Escuchar resultados del escaneo
      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results;
          });
        }
      });

      // Esperar el timeout
      await Future.delayed(const Duration(seconds: 4));
      await FlutterBluePlus. stopScan();

      if (mounted) {
        setState(() {
          _isScanning = false;
        });

        // Mostrar dialog con dispositivos encontrados
        if (_scanResults.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontraron dispositivos BLE')),
          );
        } else {
          _showDeviceSelectionDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al escanear: $e')),
        );
      }
    }
  }

  /// Mostrar diálogo para seleccionar dispositivo
  Future<void> _showDeviceSelectionDialog() async {
    final picked = await showDialog<ScanResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecciona dispositivo BLE'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _scanResults.length,
            itemBuilder: (context, index) {
              final result = _scanResults[index];
              final deviceName = result.device.platformName.isNotEmpty
                  ?  result.device.platformName
                  : 'Dispositivo desconocido';
              
              return ListTile(
                leading: Icon(
                  Icons.bluetooth,
                  color: result.rssi > -70 ? Colors.green : Colors.orange,
                ),
                title:  Text(deviceName),
                subtitle: Text(
                  'ID: ${result.device.remoteId.str}\nSeñal: ${result.rssi} dBm',
                ),
                onTap: () => Navigator.pop(context, result),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (picked != null) {
      await _connectToDevice(picked.device);
    }
  }

  /// Conectar a un dispositivo BLE específico
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      // Mostrar indicador de carga
      if (! mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child:  CircularProgressIndicator(),
        ),
      );

      // Conectar al dispositivo
      await device.connect(timeout: const Duration(seconds: 15));

      // Descubrir servicios
      final services = await device.discoverServices();
      
      // UUIDs del UART Service (Nordic UART Service)
      final uartServiceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
      final txCharUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // Notify
      final rxCharUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // Write
      
      BluetoothCharacteristic? txChar;
      BluetoothCharacteristic? rxChar;
      
      // Buscar el UART Service y sus características
      for (var service in services) {
        if (service.uuid == uartServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid == txCharUuid && char.properties.notify) {
              txChar = char;
            } else if (char.uuid == rxCharUuid && char.properties.write) {
              rxChar = char;
            }
          }
          break;
        }
      }

      // Cerrar indicador de carga
      if (!mounted) return;
      Navigator.pop(context);

      if (txChar == null || rxChar == null) {
        await device.disconnect();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el UART Service. Verifica que el dispositivo sea compatible.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Suscribirse a notificaciones del TX (recibir datos)
      await txChar.setNotifyValue(true);

      setState(() {
        _connectedDevice = device;
        _subscribedChar = txChar; // TX para recibir datos
        _rxChar = rxChar; // RX para enviar comandos
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conectado a ${device.platformName}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Cerrar indicador de carga si está abierto
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar:  $e')),
      );
    }
  }

  /// Desconectar dispositivo BLE
  Future<void> _disconnectBLE() async {
    if (_subscribedChar != null) {
      try {
        await _subscribedChar!.setNotifyValue(false);
      } catch (e) {
        print('Error al desuscribirse: $e');
      }
    }

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        print('Error al desconectar: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dispositivo desconectado'),
          ),
        );
      }
    }

    setState(() {
      _connectedDevice = null;
      _subscribedChar = null;
      _rxChar = null;
    });
  }

  // ================== FUNCIONES DE BLE ==================

  Future<void> sendTare() async {
    if (_rxChar != null) {
      try {
        await _rxChar!.write('T'.codeUnits);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tara enviada'), duration: Duration(seconds: 1)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al enviar tara: $e')),
          );
        }
      }
    }
  }

  Future<void> sendCalibration() async {
    if (_rxChar != null) {
      try {
        await _rxChar!.write('C'.codeUnits);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Calibración iniciada'), duration: Duration(seconds: 1)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al enviar calibración: $e')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conecta el dispositivo BLE primero')),
        );
      }
    }
  }

  // ================== FUNCIONES DE SESIÓN Y PERFIL ==================

  Future<void> _closeSessionOnExit() async {
    if (_sessionId != null) {
      try {
        await DatabaseHelper.instance.closeSession(_sessionId!);
      } catch (_) {}
    }
  }

  Future<void> _loadProfiles() async {
    final rows = await DatabaseHelper.instance.getAllProfiles();
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getInt('last_profile_id');
    
    setState(() {
      _profiles = rows;
      if (lastId != null && _profiles.any((p) => p['id'] == lastId)) {
        _selectedProfileId = lastId;
      } else if (_profiles.isNotEmpty) {
        _selectedProfileId = _profiles.first['id'] as int;
      } else {
        _selectedProfileId = null;
      }
    });
  }

  Future<void> _saveName() async {
    final name = _nameController.text. trim();

    if (name.isEmpty) {
      ScaffoldMessenger. of(context).showSnackBar(
        const SnackBar(content: Text('Introduce un nombre válido')),
      );
      return;
    }

    final id = await DatabaseHelper.instance.createSession(name);

    if (! mounted) return;

    setState(() {
      _savedName = name;
      _sessionId = id;
      _sessionStart = DateTime.now();
    });

    await _loadProfiles();
    
    final prof = await DatabaseHelper.instance.getProfileByName(name);
    if (!mounted) return;
    
    setState(() {
      _creatingNew = false;
      _selectedProfileId = prof != null ? prof['id'] as int : _selectedProfileId;
    });
    
    final prefs = await SharedPreferences. getInstance();
    if (prof != null) await prefs.setInt('last_profile_id', prof['id'] as int);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sesión iniciada para "$name"')),
    );
  }

  Future<void> _closeSession() async {
    if (_sessionId == null) return;

    final maxima = await DatabaseHelper.instance.getMaximaForSession(_sessionId!);
    if (maxima. isEmpty) {
      await DatabaseHelper.instance. deleteSession(_sessionId!);
    } else {
      await DatabaseHelper.instance.closeSession(_sessionId!);
    }

    if (!mounted) return;

    setState(() {
      _sessionId = null;
      _sessionStart = null;
      _savedName = '';
      _nameController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesión cerrada')),
    );
  }

  void _navigateToMode(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  String _formatDateTime(DateTime dt) {
    final l = dt.toLocal();
    final y = l.year. toString().padLeft(4, '0');
    final m = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    final ss = l.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  // ================== INTERFAZ DE USUARIO ==================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          // Indicador de estado BLE en el AppBar
          if (_connectedDevice != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(
                Icons.bluetooth_connected,
                color: Colors.green,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historial',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Calibrar',
            onPressed: sendCalibration,
          ),
        ],
      ),
      body: Center(
        child:  Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Selección de perfil
              if (_savedName.isEmpty) ...[
                if (_profiles.isNotEmpty && ! _creatingNew) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedProfileId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Selecciona perfil',
                          ),
                          items: _profiles
                              .map((p) => DropdownMenuItem(
                                    value: p['id'] as int,
                                    child: Text(p['name'] ??  ''),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedProfileId = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _selectedProfileId == null
                            ? null
                            : () async {
                                final prof = _profiles.firstWhere(
                                  (p) => p['id'] == _selectedProfileId,
                                );
                                final name = (prof['name'] ?? '').toString();
                                _nameController.text = name;
                                await _saveName();
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setInt(
                                  'last_profile_id',
                                  _selectedProfileId! ,
                                );
                              },
                        child: const Text('Usar perfil'),
                      ),
                    ],
                  ),
                  const SizedBox(height:  8),
                  TextButton(
                    onPressed:  () {
                      setState(() {
                        _creatingNew = true;
                      });
                    },
                    child: const Text('Crear nuevo perfil'),
                  ),
                ] else ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Nombre',
                      hintText: 'Introduce tu nombre',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saveName(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _saveName,
                        child: const Text('Guardar nombre'),
                      ),
                      const SizedBox(width: 8),
                      if (_profiles.isNotEmpty)
                        TextButton(
                          onPressed:  () {
                            setState(() {
                              _creatingNew = false;
                            });
                          },
                          child: const Text('Cancelar'),
                        ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 16),

              // Información de sesión y BLE
              if (_savedName.isNotEmpty) ...[
                Text(
                  '¡Hola, $_savedName!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height:  8),

                if (_sessionStart != null)
                  Text('Sesión iniciada: ${_formatDateTime(_sessionStart!)}'),

                const SizedBox(height: 12),

                // Botón de conexión BLE mejorado
                _buildBLEConnectionWidget(),

                const SizedBox(height:  16),

                // Grid de modos
                Expanded(
                  child:  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.85,
                      children: [
                        ModeCard(
                          icon: Icons.bar_chart,
                          title:  'F. Máxima',
                          description:  'Medir y registrar la fuerza máxima aplicada',
                          color: Colors.blue,
                          onTap: () {
                            if (_sessionId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Primero debes crear una sesión')),
                              );
                            } else if (_connectedDevice == null || _subscribedChar == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Conecta el dispositivo BLE antes de continuar')),
                              );
                            } else {
                              _navigateToMode(ForceMaxModePage(
                                sessionId: _sessionId!,
                                sessionName: _savedName,
                                connectedDevice: _connectedDevice!,
                                subscribedChar: _subscribedChar!,
                                onTare: sendTare,
                              ));
                            }
                          },
                        ),
                        ModeCard(
                          icon: Icons.timeline,
                          title: 'Tiempo Real',
                          description: 'Ver datos de fuerza en tiempo real',
                          color: Colors.green,
                          onTap: () {
                            if (_sessionId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Primero debes crear una sesión')),
                              );
                            } else if (_connectedDevice == null || _subscribedChar == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Conecta el dispositivo BLE antes de continuar')),
                              );
                            } else {
                              _navigateToMode(RealtimeModePage(
                                sessionId: _sessionId!,
                                sessionName: _savedName,
                                connectedDevice: _connectedDevice!,
                                subscribedChar: _subscribedChar!,
                                onTare: sendTare,
                              ));
                            }
                          },
                        ),
                        ModeCard(
                          icon: Icons.flash_on,
                          title: 'F. Explosiva',
                          description: 'Analizar el desarrollo de fuerza rápida',
                          color: Colors.red,
                          onTap: () {
                            if (_sessionId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Primero debes crear una sesión')),
                              );
                            } else if (_connectedDevice == null || _subscribedChar == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Conecta el dispositivo BLE antes de continuar')),
                              );
                            } else {
                              _navigateToMode(ExplosiveForceModePage(
                                sessionId: _sessionId!,
                                sessionName: _savedName,
                                connectedDevice: _connectedDevice!,
                                subscribedChar: _subscribedChar!,
                                onTare: sendTare,
                              ));
                            }
                          },
                        ),
                        ModeCard(
                          icon: Icons.local_fire_department,
                          title: 'F. Crítica',
                          description: 'Determinar el umbral de fuerza crítica',
                          color: Colors.deepPurple,
                          onTap: () {
                            if (_sessionId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Primero debes crear una sesión')),
                              );
                            } else if (_connectedDevice == null || _subscribedChar == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Conecta el dispositivo BLE antes de continuar')),
                              );
                            } else {
                              _launchCriticalForceMode();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Botón cerrar sesión
              if (_sessionId != null) ...[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: OutlinedButton(
                    onPressed: _closeSession,
                    child:  const Text('Cerrar sesión'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Widget de conexión BLE mejorado
  Widget _buildBLEConnectionWidget() {
    if (_connectedDevice == null) {
      return ElevatedButton. icon(
        icon: _isScanning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bluetooth_searching),
        label: Text(_isScanning ? 'Escaneando...' : 'Conectar dispositivo BLE'),
        onPressed: _isScanning ? null : _scanForDevices,
      );
    } else {
      return Card(
        child:  Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth_connected, color: Colors.green),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Conectado',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _connectedDevice!.platformName. isNotEmpty
                          ? _connectedDevice!.platformName
                          : _connectedDevice!.remoteId.str,
                      style: const TextStyle(fontSize:  12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Desconectar',
                onPressed: _disconnectBLE,
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Lanzar modo Fuerza Crítica con conexión BLE
  Future<void> _launchCriticalForceMode() async {
    // Si ya está conectado, usar dispositivo actual
    if (_connectedDevice != null && _subscribedChar != null) {
      _navigateToMode(CriticalForceModePage(
        sessionId: _sessionId!,
        sessionName: _savedName,
        connectedDevice: _connectedDevice!,
        subscribedChar: _subscribedChar!,
        onTare: sendTare,
      ));
      return;
    }

    // Si no, escanear y conectar
    await _scanForDevices();
    
    // Verificar si se conectó exitosamente
    if (_connectedDevice != null && _subscribedChar != null) {
      _navigateToMode(CriticalForceModePage(
        sessionId: _sessionId!,
        sessionName: _savedName,
        connectedDevice: _connectedDevice! ,
        subscribedChar: _subscribedChar!,
        onTare: sendTare,
      ));
    }
  }
}