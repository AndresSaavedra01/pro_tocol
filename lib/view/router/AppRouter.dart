
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:pro_tocol/controller/ProfileController.dart';
import 'package:pro_tocol/controller/ServerController.dart';
import 'package:pro_tocol/controller/TempSessionController.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

import 'package:pro_tocol/view/pages/ProfilePage.dart';
import 'package:pro_tocol/view/pages/WorkspacePage.dart';
import 'package:pro_tocol/view/components/SshErrorDisplay.dart';

class AppRouter {
  final ProfileController profileController;
  final ServerController serverController;
  final TempSessionController tempSessionController;

  AppRouter({
    required this.profileController,
    required this.serverController,
    required this.tempSessionController,
  });

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      // --- Ruta Principal: Perfiles ---
      GoRoute(
        path: '/',
        builder: (context, state) => ProfilePage(
          profileController: profileController,
          serverController: serverController,
          tempSessionController: tempSessionController,
        ),
      ),

      // --- Ruta: Workspace ---
      GoRoute(
        path: '/workspace',
        pageBuilder: (context, state) {
          // Recibimos el perfil a través de 'extra'
          final profile = state.extra as Profile;

          return CustomTransitionPage(
            key: state.pageKey,
            child: WorkspacePage(
              profile: profile,
              profileController: profileController,
              serverController: serverController,
              tempSessionController: tempSessionController,
            ),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.1), // Sube un 10% de la pantalla
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                  child: child,
                ),
              );
            },
          );
        },
      ),

      // --- Ruta: Error Display ---
      GoRoute(
        path: '/error',
        builder: (context, state) {
          // Extraemos los argumentos para la pantalla de error
          final args = state.extra as Map<String, dynamic>;
          return SshErrorDisplay(
            errorMessage: args['message'] as String,
            onRetry: args['onRetry'] as VoidCallback,
          );
        },
      ),
    ],
  );
}