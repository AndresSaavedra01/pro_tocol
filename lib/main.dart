import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Entidades ---
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/entities/chat_message_entity.dart';

// --- Enrutador ---
import 'package:pro_tocol/view/router/AppRouter.dart';

// --- Inyección de Dependencias ---
import 'injection.dart';

void main() async {
  // 1. Inicialización básica
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Supabase Auth
  await Supabase.initialize(
    url: 'https://syfjxpeaqpdelyyueise.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN5Zmp4cGVhcXBkZWx5eXVlaXNlIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM1ODg3OCwiZXhwIjoyMDk0OTM0ODc4fQ.02KUOemRQJ5NVKv6_8I6acyffMmbzDZq6fH0m8z425A',
  );

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ServerConfigSchema, AiConfigSchema, ChatMessageEntitySchema,],
    directory: dir.path,
  );

  // 2. Inicializar el contenedor de dependencias (GetIt)
  await setupDependencies(isar);

  // 3. Enrutador
  final appRouter = AppRouter();

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