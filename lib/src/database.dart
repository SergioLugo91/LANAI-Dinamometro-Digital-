// Importamos las librerías necesarias
import 'package:path/path.dart'; // Permite construir rutas de archivos de manera segura
import 'package:path_provider/path_provider.dart'; // Proporciona rutas a directorios del sistema (ej. Documents)
import 'package:sqflite/sqflite.dart'; // Plugin de Flutter para usar SQLite (base de datos local)

// Clase principal que maneja la base de datos
class DatabaseHelper {
  // Obtiene todos los valores de fuerza crítica de una sesión específica
  Future<List<Map<String, dynamic>>> getCriticalForceForSession(int sessionId) async {
    final db = await instance.database;
    return await db.query(
      'critical_force',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp DESC',
    );
  }
  // Singleton: solo habrá una instancia de esta clase durante toda la app
  static final DatabaseHelper instance = DatabaseHelper._init();

  // Variable privada que almacenará la conexión activa con la base de datos
  static Database? _database;

  // Constructor privado (solo accesible dentro de la clase)
  DatabaseHelper._init();

  // Getter que devuelve la base de datos abierta o la crea si no existe
  Future<Database> get database async {
    if (_database != null) return _database!; // Si ya está abierta, la devuelve
    _database = await _initDB('dinamometro.db'); // Si no, la inicializa
    return _database!;
  }

  // Inicializa la base de datos SQLite dentro del directorio de la app
  Future<Database> _initDB(String fileName) async {
    // Obtiene la carpeta de documentos del dispositivo (donde se puede guardar la BD)
    final documentsDirectory = await getApplicationDocumentsDirectory();
    // Une la ruta de la carpeta con el nombre del archivo .db
    final path = join(documentsDirectory.path, fileName);
    // Abrir o crear la base de datos; versión 3 introduce tabla `explosive_force`
    return await openDatabase(path, version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  // Método que se ejecuta solo la primera vez, cuando la base se crea
  Future _createDB(Database db, int version) async {
    // Tabla "critical_force" → guarda los valores de fuerza crítica calculados
    await db.execute('''
      CREATE TABLE critical_force (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        value REAL NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    // Tabla "explosive_force" → guarda los valores de tasa de desarrollo de fuerza
    await db.execute('''
      CREATE TABLE explosive_force (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        hand TEXT NOT NULL,
        rate REAL NOT NULL,
        max_force REAL NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    // Tabla "profiles" → almacena perfiles de usuario separados de las sesiones
    await db.execute('''
      CREATE TABLE profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    // Tabla "sessions" → almacena las sesiones de los usuarios (ahora con profile_id)
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        profile_id INTEGER,
        created_at TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE SET NULL
      )
    ''');

    // Tabla "maxima" → guarda los valores de fuerza máxima alcanzados
    await db.execute('''
      CREATE TABLE maxima (
        id INTEGER PRIMARY KEY AUTOINCREMENT,       -- ID del registro
        session_id INTEGER NOT NULL,                -- Relación con la sesión
        hand TEXT NOT NULL,                         -- Mano medida (izquierda/derecha)
        value REAL NOT NULL,                        -- Valor máximo (número decimal)
        timestamp TEXT NOT NULL,                    -- Fecha y hora del registro
        FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');
  }

  // Migración de versión 1 → 2: crear tabla profiles y poblar profile_id en sessions
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Crear tabla profiles
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL
        )
      ''');

      // Añadir columna profile_id a sessions
      await db.execute('''
        ALTER TABLE sessions ADD COLUMN profile_id INTEGER
      ''');

      // Poblar profiles a partir de los nombres existentes en sessions
      final rows = await db.rawQuery('SELECT DISTINCT name FROM sessions WHERE name IS NOT NULL');
      for (var r in rows) {
        final name = (r['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final now = DateTime.now().toIso8601String();
        // Insert profile si no existe
        final existing = await db.query('profiles', where: 'name = ?', whereArgs: [name]);
        int profileId;
        if (existing.isEmpty) {
          profileId = await db.insert('profiles', {'name': name, 'created_at': now});
        } else {
          profileId = existing.first['id'] as int;
        }
        // Actualizar sesiones con ese nombre
        await db.update('sessions', {'profile_id': profileId}, where: 'name = ?', whereArgs: [name]);
      }
    }
    
    if (oldVersion < 3) {
      // Crear tabla explosive_force para versión 3
      await db.execute('''
        CREATE TABLE IF NOT EXISTS explosive_force (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          hand TEXT NOT NULL,
          rate REAL NOT NULL,
          max_force REAL NOT NULL,
          timestamp TEXT NOT NULL,
          FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        )
      ''');
    }
  }

  // ======================= OPERACIONES CRUD =======================

  // Crea una nueva sesión en la tabla "sessions"
  Future<int> createSession(String name) async {
    final db = await instance.database; // Obtiene la base de datos activa
    final now = DateTime.now().toIso8601String(); // Fecha actual en formato ISO
    // Asegurarse de que exista el perfil y obtener profile_id
    final profileId = await createProfile(name);
    // Inserta la nueva sesión y devuelve el ID generado
    return await db.insert('sessions', {
      'name': name,
      'profile_id': profileId,
      'created_at': now,
      'active': 1,
    });
  }

  // Crea o devuelve el id de un profile existente
  Future<int> createProfile(String name) async {
    final db = await instance.database;
    final rows = await db.query('profiles', where: 'name = ?', whereArgs: [name]);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    final now = DateTime.now().toIso8601String();
    return await db.insert('profiles', {'name': name, 'created_at': now});
  }

  // Obtiene todos los perfiles
  Future<List<Map<String, dynamic>>> getAllProfiles() async {
    final db = await instance.database;
    return await db.query('profiles', orderBy: 'created_at DESC');
  }

  // Busca un perfil por nombre
  Future<Map<String, dynamic>?> getProfileByName(String name) async {
    final db = await instance.database;
    final rows = await db.query('profiles', where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // Guarda un valor máximo (por ejemplo, fuerza máxima medida)
  Future<int> saveMax(int sessionId, String hand, double value) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('maxima', {
      'session_id': sessionId,
      'hand': hand,
      'value': value,
      'timestamp': now,
    });
  }

  // Guarda un valor de fuerza crítica
  Future<int> saveCriticalForce(int sessionId, double value) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('critical_force', {
      'session_id': sessionId,
      'value': value,
      'timestamp': now,
    });
  }

  // Guarda un valor de fuerza explosiva (tasa de desarrollo)
  Future<int> saveExplosiveForce(int sessionId, String hand, double rate, double maxForce) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('explosive_force', {
      'session_id': sessionId,
      'hand': hand,
      'rate': rate,
      'max_force': maxForce,
      'timestamp': now,
    });
  }

  // Obtiene todos los valores máximos de una sesión específica
  Future<List<Map<String, dynamic>>> getMaximaForSession(int sessionId) async {
    final db = await instance.database;
    return await db.query(
      'maxima',
      where: 'session_id = ?',
      whereArgs: [sessionId], // Reemplaza el ? con el valor del sessionId
      orderBy: 'timestamp DESC', // Ordena del más reciente al más antiguo
    );
  }

  // Obtiene todos los valores de fuerza explosiva de una sesión específica
  Future<List<Map<String, dynamic>>> getExplosiveForceForSession(int sessionId) async {
    final db = await instance.database;
    return await db.query(
      'explosive_force',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp DESC',
    );
  }

  // Obtiene todas las sesiones registradas (activas o no)
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await instance.database;
    return await db.query(
      'sessions',
      orderBy: 'created_at DESC', // Las más recientes primero
    );
  }

  // Obtiene sesiones con filtros opcionales: profile_id y día concreto
  Future<List<Map<String, dynamic>>> getSessionsFiltered({int? profileId, DateTime? day}) async {
    final db = await instance.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];
    if (profileId != null) {
      whereClauses.add('profile_id = ?');
      whereArgs.add(profileId);
    }
    if (day != null) {
      final start = DateTime(day.year, day.month, day.day).toIso8601String();
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59).toIso8601String();
      whereClauses.add('created_at BETWEEN ? AND ?');
      whereArgs.addAll([start, end]);
    }
    final where = whereClauses.isEmpty ? null : whereClauses.join(' AND ');
    return await db.query('sessions', where: where, whereArgs: whereArgs, orderBy: 'created_at DESC');
  }

  // Marca una sesión como cerrada (cambia active de 1 a 0)
  Future<int> closeSession(int sessionId) async {
    final db = await instance.database;
    return await db.update(
      'sessions',
      {'active': 0}, // Actualiza el campo "active"
      where: 'id = ?', // Filtra por ID
      whereArgs: [sessionId],
    );
  }

  // Elimina una sesión por completo (y sus entradas por cascade)
  Future<int> deleteSession(int sessionId) async {
    final db = await instance.database;
    return await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // Cierra la conexión con la base de datos (buena práctica al salir de la app)
  Future close() async {
    final db = await instance.database;
    await db.close(); // Cierra la conexión
    _database = null; // Limpia la referencia para poder reabrir después
  }
}
