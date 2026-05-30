import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// --- Entidades ---
import 'package:pro_tocol/model/entities/Profile.dart';

// --- Páginas ---
import 'package:pro_tocol/view/pages/ProfilePage.dart';
import 'package:pro_tocol/view/pages/AiSettingsPage.dart';
import 'package:pro_tocol/view/pages/WorkspacePage.dart';
import 'package:pro_tocol/view/components/SshErrorDisplay.dart';

class AppRouter {

  AppRouter();

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      // --- Ruta Principal: Perfiles ---
      GoRoute(
        path: '/',
        builder: (context, state) => const ProfilePage(), // Limpio de constructores
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
              // ELIMINADO: Los controladores se inyectan dentro de WorkspacePage o sus Tabs
            ),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                  child: child,
                ),
              );
            },
          );
        },
      ),

      GoRoute(
        path: '/ai-settings',
        builder: (context, state) => const AiSettingsPage(),
      ),

      // --- Ruta: Error Display ---
      GoRoute(
        path: '/error',
        builder: (context, state) {
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