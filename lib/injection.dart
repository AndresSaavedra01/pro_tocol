import 'package:get_it/get_it.dart';
import 'package:isar/isar.dart';

// --- DAOs ---
import 'package:pro_tocol/model/daos/ProfileDAO.dart';
import 'package:pro_tocol/model/daos/ServerConfigDAO.dart';

// --- Repositorios ---
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';
import 'package:pro_tocol/model/repositories/TempSessionRepository.dart';

// --- Lógica / Managers ---
import 'package:pro_tocol/logic/command_history_manager.dart';

// --- Controladores Base ---
import 'package:pro_tocol/controller/ProfileController.dart';
import 'package:pro_tocol/controller/TempSessionController.dart';
import 'package:pro_tocol/controller/SshKeyController.dart';

// --- Controladores Modulares (Nuevos) ---
import 'package:pro_tocol/controller/ServerConnectionController.dart';
import 'package:pro_tocol/controller/ServerAppsController.dart';
import 'package:pro_tocol/controller/ServerTemplateController.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies(Isar isar) async {
  // 1. DAOs
  final profileDAO = ProfileDAO(isar);
  final serverConfigDAO = ServerConfigDAO(isar);

  // 2. Repositorios
  getIt.registerLazySingleton<ProfileRepository>(() => ProfileRepository(profileDAO));
  getIt.registerLazySingleton<ServerRepository>(() => ServerRepository(serverConfigDAO));
  getIt.registerLazySingleton<TempSessionRepository>(() => TempSessionRepository());

  // 3. Managers
  getIt.registerLazySingleton<CommandHistoryManager>(() => CommandHistoryManager());

  // 4. Controladores Globales
  getIt.registerLazySingleton<SshKeyController>(() => SshKeyController());

  getIt.registerLazySingleton<ProfileController>(() => ProfileController(
    getIt<ProfileRepository>(),
  ));

  getIt.registerLazySingleton<TempSessionController>(() => TempSessionController(
    getIt<TempSessionRepository>(),
    getIt<CommandHistoryManager>(),
  ));

  // 5. Nuevos Controladores del Servidor
  getIt.registerLazySingleton<ServerConnectionController>(() => ServerConnectionController(
    getIt<ServerRepository>(),
    getIt<ProfileRepository>(),
    getIt<SshKeyController>(),
  ));

  getIt.registerLazySingleton<ServerAppsController>(() => ServerAppsController(
    getIt<ServerConnectionController>(),
    getIt<CommandHistoryManager>(),
  ));

  getIt.registerLazySingleton<ServerTemplateController>(() => ServerTemplateController(
    getIt<ServerConnectionController>(),
    getIt<CommandHistoryManager>(),
  ));
}