import 'package:get_it/get_it.dart';
import 'package:isar/isar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pro_tocol/controller/KeyController.dart';
import 'package:pro_tocol/model/repositories/ChatHistoryRepository.dart';
import 'package:pro_tocol/model/services/SSHService.dart';
import 'package:xterm/xterm.dart';

// --- DAOs ---
import 'package:pro_tocol/model/daos/AiConfigDAO.dart';
import 'package:pro_tocol/model/daos/ServerConfigDAO.dart';

// --- Servicios ---
import 'package:pro_tocol/model/services/ia_service.dart';
import 'package:pro_tocol/model/services/AuthService.dart';

// --- Repositorios ---
import 'package:pro_tocol/model/repositories/AiConfigRepository.dart';
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';
import 'package:pro_tocol/model/repositories/TempSessionRepository.dart';

// --- Lógica / Managers ---
import 'package:pro_tocol/logic/command_history_manager.dart';

// --- Controladores Base ---
import 'package:pro_tocol/controller/ProfileController.dart';
import 'package:pro_tocol/controller/TempSessionController.dart';
import 'package:pro_tocol/controller/SshKeyController.dart';

// --- Controladores Modulares ---
import 'package:pro_tocol/controller/ServerConnectionController.dart';
import 'package:pro_tocol/controller/ServerAppsController.dart';
import 'package:pro_tocol/controller/ServerTemplateController.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies(Isar isar) async {
  // 1. DAOs
  final aiConfigDAO = AiConfigDAO(isar);
  final serverConfigDAO = ServerConfigDAO(isar);

  getIt.registerLazySingleton<AuthService>(() => AuthService());
  getIt.registerLazySingleton<SSHService>(() => SSHService()); // ¡Nuevo!

  getIt.registerLazySingleton<KeyController>(() => KeyController(
    isar: isar,
    sshService: getIt<SSHService>(),
  ));

  // 3. Repositorios
  getIt.registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());
  getIt.registerLazySingleton<ProfileRepository>(() => ProfileRepository(getIt<AuthService>()));
  getIt.registerLazySingleton<ServerRepository>(() => ServerRepository(serverConfigDAO));
  getIt.registerLazySingleton<TempSessionRepository>(() => TempSessionRepository());

  // 3.1 Servicio IA
  getIt.registerLazySingleton<IAService>(() => IAService());

  // 4. Managers
  getIt.registerLazySingleton<CommandHistoryManager>(() => CommandHistoryManager());

  // 4.1 Terminal
  getIt.registerLazySingleton<Terminal>(() => Terminal(maxLines: 10000));

  // 5. Controladores
  getIt.registerLazySingleton<SshKeyController>(() => SshKeyController());

  getIt.registerLazySingleton<ProfileController>(() => ProfileController(
    getIt<ProfileRepository>(),
  ));

  getIt.registerLazySingleton<TempSessionController>(() => TempSessionController(
    getIt<TempSessionRepository>(),
    getIt<CommandHistoryManager>(),
  ));

  getIt.registerLazySingleton<ServerConnectionController>(() => ServerConnectionController(
    getIt<ServerRepository>(),
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

  getIt.registerLazySingleton<ChatHistoryRepository>(() => ChatHistoryRepository(isar));



}