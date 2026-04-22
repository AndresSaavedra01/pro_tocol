import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

// --- Entidades ---
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

// --- Enrutador ---
import 'package:pro_tocol/view/router/AppRouter.dart';

// --- Inyección de Dependencias ---
import 'injection.dart'; // Asegúrate de importar el archivo que acabamos de crear

void main() async {
  // 1. Inicialización básica
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ProfileSchema, ServerConfigSchema],
    directory: dir.path,
  );

  // 2. Inicializar el contenedor de dependencias (GetIt)
  await setupDependencies(isar);

  // 3. Enrutador
  // Lo ideal es que entres a tu AppRouter.dart y le quites
  // los controladores del constructor, dejándolo limpio así:
  final appRouter = AppRouter();

  /* * NOTA: Si mientras refactorizas, tu AppRouter TODAVÍA pide
   * los controladores en el constructor y da error, puedes pasar
   * temporalmente las dependencias desde GetIt de la siguiente forma:
   * * final appRouter = AppRouter(
   * profileController: getIt<ProfileController>(),
   * serverController: getIt<ServerConnectionController>(), // O tu fachada temporal
   * tempSessionController: getIt<TempSessionController>(),
   * );
   */

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
    return MaterialApp.router(
      title: 'Pro-Tocol SSH',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter.router,
    );
  }
}