import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_tocol/controller/SshKeyController.dart';

// --- Entidades ---
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

// --- DAOs ---
import 'package:pro_tocol/model/daos/ProfileDAO.dart';
import 'package:pro_tocol/model/daos/ServerConfigDAO.dart';

// --- Repositorios ---
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';
import 'package:pro_tocol/model/repositories/TempSessionRepository.dart';

// --- Controladores ---
import 'package:pro_tocol/controller/ProfileController.dart';
import 'package:pro_tocol/controller/ServerController.dart';
import 'package:pro_tocol/controller/TempSessionController.dart';

// --- Lógica (Tu rama) ---
import 'package:pro_tocol/logic/command_history_manager.dart';

// --- Enrutador (Predominante de develop) ---
import 'package:pro_tocol/view/router/AppRouter.dart';

void main() async {
  // 1. Inicialización básica
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ProfileSchema, ServerConfigSchema],
    directory: dir.path,
  );

  // 2. Inyección de Dependencias
  final profileDAO = ProfileDAO(isar);
  final serverConfigDAO = ServerConfigDAO(isar);

  final profileRepository = ProfileRepository(profileDAO);
  final serverRepository = ServerRepository(serverConfigDAO);
  final tempSessionRepository = TempSessionRepository();

  // Instanciamos tu nueva lógica
  final commandHistoryManager = CommandHistoryManager();

  // 3. Controladores (Adaptados para incluir el commandHistoryManager)
  final profileController = ProfileController(profileRepository);
  
  // OJO: Aquí pasamos el commandHistoryManager como en tu rama local
  final serverController = ServerController(
    serverRepository, 
    profileRepository, 
    commandHistoryManager,
    SshKeyController()
  );
  
  final tempSessionController = TempSessionController(
    tempSessionRepository, 
    commandHistoryManager,
  );

  // 4. Enrutador (Estructura de develop)
  final appRouter = AppRouter(
    profileController: profileController,
    serverController: serverController,
    tempSessionController: tempSessionController,
  );

  runApp(MyApp(appRouter: appRouter));
}

class MyApp extends StatelessWidget {
  final AppRouter appRouter;

  const MyApp({
    super.key,
    required this.appRouter,
  });

  @override
  Widget build(BuildContext context) {
    // Predomina el uso de routerConfig de develop
    return MaterialApp.router(
      title: 'Pro-Tocol SSH',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter.router,
    );
  }
}