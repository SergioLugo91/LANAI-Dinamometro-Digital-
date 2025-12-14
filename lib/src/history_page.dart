import 'package:flutter/material.dart';
import 'database.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Future<List<Map<String, dynamic>>> _getCriticalForce(int sessionId) async {
    return await DatabaseHelper.instance.getCriticalForceForSession(sessionId);
  }

  Future<List<Map<String, dynamic>>> _getExplosiveForce(int sessionId) async {
    return await DatabaseHelper.instance.getExplosiveForceForSession(sessionId);
  }
  late Future<List<Map<String, dynamic>>> _sessionsFuture;
  List<Map<String, dynamic>> _profiles = [];
  int? _filterProfileId;
  DateTime? _filterDay;

  @override
  void initState() {
    super.initState();
    _loadProfilesAndSessions();
  }

  Future<void> _loadProfilesAndSessions() async {
    final profiles = await DatabaseHelper.instance.getAllProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
    });
    _reloadSessions();
  }

  void _reloadSessions() {
    setState(() {
      _sessionsFuture = DatabaseHelper.instance.getSessionsFiltered(profileId: _filterProfileId, day: _filterDay);
    });
  }

  Future<List<Map<String, dynamic>>> _getMaxima(int sessionId) async {
    return await DatabaseHelper.instance.getMaximaForSession(sessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de sesiones'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _filterProfileId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Perfil'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
                      ..._profiles.map((p) => DropdownMenuItem<int?>(value: p['id'] as int, child: Text(p['name'] ?? ''))),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _filterProfileId = v;
                      });
                      _reloadSessions();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _filterDay ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() {
                        _filterDay = picked;
                      });
                      _reloadSessions();
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_filterDay == null
                      ? 'Filtrar por día'
                      : '${_filterDay!.year}-${_filterDay!.month.toString().padLeft(2, '0')}-${_filterDay!.day.toString().padLeft(2, '0')}'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _filterDay = null;
                      _filterProfileId = null;
                    });
                    _reloadSessions();
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: 'Limpiar filtros',
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _sessionsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (!snap.hasData || snap.data!.isEmpty) return const Center(child: Text('No hay sesiones registradas'));
                final sessions = snap.data!;
                return ListView.builder(
                  itemCount: sessions.length,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final id = s['id'] as int;
                    final name = s['name'] as String;
                    final createdAt = s['created_at'] as String;
                    final active = s['active'] as int;
                    final dt = DateTime.parse(createdAt).toLocal();
                    final createdShort = '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                    return ExpansionTile(
                      key: ValueKey(id),
                      title: Text('$name — $createdShort'),
                      subtitle: Text(active == 1 ? 'Activa' : 'Cerrada'),
                      children: [
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getMaxima(id),
                          builder: (context, mSnap) {
                            if (mSnap.connectionState != ConnectionState.done){
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            } 
                            final maxima = mSnap.data ?? [];
                            if (maxima.isEmpty) return const ListTile(title: Text('No hay máximos guardados'));
                            return Column(
                              children: maxima.map((mx) {
                                final hand = mx['hand'] ?? '';
                                final value = mx['value'] ?? 0;
                                return ListTile(
                                  leading: Icon(hand == 'right' ? Icons.pan_tool : Icons.pan_tool_outlined),
                                  title: Text('Máx: ${double.parse(value.toString()).toStringAsFixed(1)} kg'),
                                  subtitle: Text('Mano: $hand'),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        // Mostrar valores de fuerza crítica guardados
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getCriticalForce(id),
                          builder: (context, cSnap) {
                            if (cSnap.connectionState != ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final crits = cSnap.data ?? [];
                            if (crits.isEmpty) {
                              return const ListTile(title: Text('No hay valores de fuerza crítica guardados'));
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                                  child: Text('Fuerza crítica:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                ...crits.map((cf) {
                                  final value = cf['value'] ?? 0;
                                  final ts = cf['timestamp'] ?? '';
                                  String? dateStr;
                                  if (ts is String && ts.isNotEmpty) {
                                    try {
                                      final dt = DateTime.parse(ts).toLocal();
                                      dateStr = '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                                    } catch (_) {}
                                  }
                                  return ListTile(
                                    leading: const Icon(Icons.show_chart),
                                    title: Text('F. crítica: ${double.parse(value.toString()).toStringAsFixed(2)} kg'),
                                    subtitle: dateStr != null ? Text('Guardado: $dateStr') : null,
                                  );
                                }).toList(),
                              ],
                            );
                          },
                        ),
                        // Mostrar valores de fuerza explosiva guardados
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getExplosiveForce(id),
                          builder: (context, eSnap) {
                            if (eSnap.connectionState != ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final exps = eSnap.data ?? [];
                            if (exps.isEmpty) {
                              return const ListTile(title: Text('No hay valores de fuerza explosiva guardados'));
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                                  child: Text('Fuerza explosiva:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                ...exps.map((ef) {
                                  final hand = ef['hand'] ?? '';
                                  final rate = ef['rate'] ?? 0;
                                  final maxForce = ef['max_force'] ?? 0;
                                  final ts = ef['timestamp'] ?? '';
                                  String? dateStr;
                                  if (ts is String && ts.isNotEmpty) {
                                    try {
                                      final dt = DateTime.parse(ts).toLocal();
                                      dateStr = '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                                    } catch (_) {}
                                  }
                                  return ListTile(
                                    leading: Icon(hand == 'right' ? Icons.pan_tool : Icons.pan_tool_outlined),
                                    title: Text('Tasa: ${double.parse(rate.toString()).toStringAsFixed(2)} kg/s'),
                                    subtitle: Text('Mano: $hand | Máx: ${double.parse(maxForce.toString()).toStringAsFixed(2)} kg'),
                                    trailing: dateStr != null ? Text(dateStr, style: const TextStyle(fontSize: 12)) : null,
                                  );
                                }).toList(),
                              ],
                            );
                          },
                        ),
                        const Divider(),
                        OverflowBar(
                          children: [
                            TextButton.icon(
                              onPressed: active == 1
                                  ? null
                                  : () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Confirmar borrado'),
                                          content: const Text('¿Borrar esta sesión y sus datos? Esta acción no se puede deshacer.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancelar')),
                                            TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Borrar')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await DatabaseHelper.instance.deleteSession(id);
                                        _reloadSessions();
                                      }
                                    },
                              icon: const Icon(Icons.delete_forever),
                              label: active == 1 ? const Text('No se puede borrar (activa)') : const Text('Borrar sesión'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

