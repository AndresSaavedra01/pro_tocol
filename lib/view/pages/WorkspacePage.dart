import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/entities/Profile.dart';
import 'package:pro_tocol/model/repositories/ServerRepository.dart';

import 'package:pro_tocol/view/components/connection_dialog.dart';
import 'package:pro_tocol/view/components/custom_sidebar.dart';
import 'package:pro_tocol/view/pages/server_tabs/UserProfileTab.dart';

import '../../controller/ServerConnectionController.dart';
import '../../controller/TempSessionController.dart';
import '../../controller/ProfileController.dart';
import '../../injection.dart';
import '../../model/entities/TempSessionConfig.dart';
import '../theme/AppColors.dart';
import 'ServerPage.dart';
import 'TempSessionPage.dart';
import 'DistroLogsPage.dart';

// Los índices del BottomNavigationBar
// 0 = Inicio/Conexión activa
// 1 = Distro & Logs
// 2 = Perfil
const int _kIdxHome = 0;
const int _kIdxDistroLogs = 1;
const int _kIdxProfile = 2;

// Estado interno de la conexión activa (independiente del BottomNav)
enum _ConnectionState { none, loading, serverConnected, tempConnected }

class WorkspacePage extends StatefulWidget {
  final Profile profile;

  const WorkspacePage({
    super.key,
    required this.profile,
  });

  ServerConnectionController get _connectionController =>
      getIt<ServerConnectionController>();
  TempSessionController get _tempSessionController =>
      getIt<TempSessionController>();
  ServerRepository get _serverRepository => getIt<ServerRepository>();

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  // Índice activo del BottomNavigationBar
  int _bottomNavIndex = _kIdxHome;

  // Estado de la conexión SSH activa
  _ConnectionState _connState = _ConnectionState.none;

  ServerConfig? _selectedServer;
  TempSessionConfig? _selectedTempSession;

  final List<TempSessionConfig> _tempConfigs = [];
  List<ServerConfig> _servers = [];

  @override
  void initState() {
    super.initState();
    _refreshServers();
  }

  Future<void> _refreshServers() async {
    try {
      final servers = await widget._serverRepository
          .getServersByProfileId(widget.profile.id);
      if (mounted) {
        setState(() {
          _servers = servers;
        });
      }
    } catch (e) {
      debugPrint('Error cargando servidores: $e');
    }
  }

  // Vuelve a la vista de inicio SIN destruir la conexión activa
  void _goHome() {
    setState(() {
      _bottomNavIndex = _kIdxHome;
      // Solo limpiamos la conexión si realmente no hay ninguna activa
      // (p.ej. al borrar un servidor). De lo contrario, mantenemos
      // _selectedServer / _selectedTempSession intactos.
    });
  }

  // Limpia completamente la conexión (sólo para borrado o error)
  void _clearConnection() {
    setState(() {
      _connState = _ConnectionState.none;
      _selectedServer = null;
      _selectedTempSession = null;
      _bottomNavIndex = _kIdxHome;
    });
  }

  Future<void> _selectServer(ServerConfig server) async {
    setState(() {
      _connState = _ConnectionState.loading;
      _selectedServer = server;
      _selectedTempSession = null;
      _bottomNavIndex = _kIdxHome;
    });

    try {
      await widget._connectionController.connectToServer(server);
      if (mounted) {
        setState(() => _connState = _ConnectionState.serverConnected);
      }
    } catch (e) {
      if (mounted) {
        _clearConnection();
        context.push('/error', extra: {
          'message': e.toString(),
          'onRetry': () => context.pop(),
        });
      }
    }
  }

  Future<void> _selectTempSession(TempSessionConfig config) async {
    setState(() {
      _connState = _ConnectionState.loading;
      _selectedTempSession = config;
      _selectedServer = null;
      _bottomNavIndex = _kIdxHome;
    });

    try {
      await widget._tempSessionController.createAndConnect(
        host: config.host,
        username: config.username,
        port: config.port,
        password: config.password,
        keyPairId: config.keyPairId,
      );

      if (mounted) {
        setState(() => _connState = _ConnectionState.tempConnected);
      }
    } catch (e) {
      if (mounted) {
        _clearConnection();
        context.push('/error', extra: {
          'message': e.toString(),
          'onRetry': () => context.pop(),
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: CustomSidebar(
        servers: _servers,
        tempSessions: _tempConfigs
            .map((c) => ServerConfig()
              ..host = c.host
              ..username = c.username
              ..id = c.host.hashCode)
            .toList(),
        activeServer: _selectedServer,
        activeTempSession: _selectedTempSession != null
            ? (ServerConfig()
              ..host = _selectedTempSession!.host
              ..id = _selectedTempSession!.host.hashCode)
            : null,
        onAddServer: () => _showServerDialog(context),
        onSelectServer: _selectServer,
        onEditServer: (s) => _showEditServerDialog(context, s),
        onDeleteServer: (s) {
          _confirmDelete(context, s.host, () async {
            await widget._connectionController.deleteServer(s.id);
            if (_selectedServer?.id == s.id) _clearConnection();
            _refreshServers();
          });
        },
        onAddTempSession: () => _showTempSessionDialog(context),
        onSelectTempSession: (s) {
          final config = _tempConfigs.firstWhere((c) => c.host == s.host);
          _selectTempSession(config);
        },
        onEditTempSession: (s) {
          final config = _tempConfigs.firstWhere((c) => c.host == s.host);
          _showEditTempSessionDialog(context, config);
        },
        onDeleteTempSession: (s) {
          _confirmDelete(context, s.host, () async {
            await widget._tempSessionController.disconnectAndRemove(s.host);
            setState(() {
              _tempConfigs.removeWhere((c) => c.host == s.host);
              if (_selectedTempSession?.host == s.host) _clearConnection();
            });
          });
        },
      ),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _getAppBarTitle(),
            key: ValueKey<String>(_getAppBarTitle()),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined, size: 20),
            onPressed: () => context.push('/ai-settings'),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () async {
              await getIt<ProfileController>().signOut();
              if (context.mounted) {
                context.go('/');
              }
            },
          )
        ],
      ),
      // ─── CUERPO: IndexedStack preserva los widgets en memoria ───────────
      body: Container(
        width: double.infinity,
        decoration: AppTheme.mainBackground,
        child: IndexedStack(
          index: _bottomNavIndex,
          children: [
            // Índice 0: Home / conexión activa
            _buildHomeOrConnectionView(),
            // Índice 1: Distro & Logs
            DistroLogsPage(
              activeServer: _selectedServer != null
                  ? widget._connectionController
                      .getActiveServer(_selectedServer!.id)
                  : null,
              activeSession: _selectedTempSession != null
                  ? widget._tempSessionController
                      .getValidSession(_selectedTempSession!.host)
                  : null,
            ),
            // Índice 2: Perfil
            UserProfileTab(profile: widget.profile),
          ],
        ),
      ),
      // ────────────────────────────────────────────────────────────────────
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        backgroundColor: AppColors.background,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        onTap: (index) {
          setState(() => _bottomNavIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Inicio'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history, size: 20), label: 'Distro & Logs'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }

  /// Vista de inicio (índice 0 del IndexedStack).
  /// Muestra loading, ServerPage, TempSessionPage, o el welcome según el estado.
  Widget _buildHomeOrConnectionView() {
    switch (_connState) {
      case _ConnectionState.loading:
        return const Center(
          key: ValueKey('loading'),
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      case _ConnectionState.serverConnected:
        // ServerPage permanece vivo gracias al IndexedStack
        return ServerPage(
          key: ValueKey('server_${_selectedServer!.id}'),
          serverConfig: _selectedServer!,
        );
      case _ConnectionState.tempConnected:
        return TempSessionPage(
          key: ValueKey('temp_${_selectedTempSession!.host}'),
          tempConfig: _selectedTempSession!,
        );
      case _ConnectionState.none:
      default:
        return _buildWelcomeView();
    }
  }

  String _getAppBarTitle() {
    if (_bottomNavIndex == _kIdxDistroLogs) return 'Distro & Logs';
    if (_bottomNavIndex == _kIdxProfile) return 'Mi Perfil';
    // Índice home
    switch (_connState) {
      case _ConnectionState.serverConnected:
        return 'Servidor';
      case _ConnectionState.tempConnected:
        return 'Terminal';
      case _ConnectionState.loading:
        return 'Conectando...';
      default:
        return 'Inicio';
    }
  }

  Widget _buildWelcomeView() {
    return Padding(
      key: const ValueKey('welcome_view'),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: AppTheme.glassCard,
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 35,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person,
                      color: AppColors.textPrimary, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('¡Bienvenido!',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Perfil: ${widget.profile.profileName}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 16)),
                const SizedBox(height: 20),
                const Text(
                  'Usa el menú lateral para gestionar\nservidores y sesiones',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, String itemName, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogDark,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border)),
        title: const Text('¿Eliminar conexión?',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold)),
        content: Text(
            '¿Estás seguro de que deseas eliminar "$itemName"? Esta acción no se puede deshacer.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              context.pop();
              onConfirm();
            },
            child: const Text('Eliminar',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showServerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => ConnectionFormDialog(
        title: 'Crear Servidor',
        subtitle: 'Se guardará en Isar y se conectará ahora',
        buttonText: 'Guardar y Conectar',
        onSubmit: (host, user, pass, port, privKey, pubKey) async {
          try {
            String? finalKeyId;
            if (privKey != null && privKey.isNotEmpty) {
              finalKeyId = await widget
                  ._connectionController.sshKeyController
                  .saveManualKey(privKey);
            }

            final newServer =
                await widget._connectionController.createAndLinkServer(
              profileId: widget.profile.id,
              host: host,
              username: user,
              port: port,
              password: pass,
              keyPairId: finalKeyId,
            );

            if (context.mounted) {
              dialogContext.pop();
              await _refreshServers();
              _selectServer(newServer);
            }
          } catch (e) {
            if (context.mounted) {
              context.push('/error', extra: {
                'message': e.toString(),
                'onRetry': () => context.pop(),
              });
            }
          }
        },
      ),
    );
  }

  void _showEditServerDialog(BuildContext context, ServerConfig server) {
    showDialog(
      context: context,
      builder: (dialogContext) => ConnectionFormDialog(
        title: 'Editar Servidor',
        subtitle: 'Actualiza los datos de conexión',
        buttonText: 'Guardar Cambios',
        initialHost: server.host,
        initialUser: server.username,
        initialPass: server.password,
        initialPort: server.port,
        onSubmit: (host, user, pass, port, privKey, pubKey) async {
          server.host = host;
          server.username = user;
          server.password = pass;
          server.port = port;

          if (privKey != null && privKey.isNotEmpty) {
            await widget._connectionController.sshKeyController
                .saveManualKey(privKey);
          }

          await widget._connectionController.updateServer(server);

          if (context.mounted) {
            dialogContext.pop();
            _refreshServers();
          }
        },
      ),
    );
  }

  void _showTempSessionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => ConnectionFormDialog(
        title: 'Nueva Sesión Temporal',
        subtitle: 'Los datos no se guardarán al cerrar la app',
        buttonText: 'Conectar Ahora',
        onSubmit: (host, user, pass, port, privKey, pubKey) async {
          final config = TempSessionConfig(
            host: host,
            username: user,
            password: pass,
            port: port,
          );
          setState(() => _tempConfigs.add(config));
          dialogContext.pop();
          _selectTempSession(config);
        },
      ),
    );
  }

  void _showEditTempSessionDialog(
      BuildContext context, TempSessionConfig config) {
    showDialog(
      context: context,
      builder: (dialogContext) => ConnectionFormDialog(
        title: 'Editar Sesión Temporal',
        subtitle: 'Actualiza los datos para esta sesión',
        buttonText: 'Actualizar',
        initialHost: config.host,
        initialUser: config.username,
        initialPass: config.password,
        initialPort: config.port,
        onSubmit: (host, user, pass, port, privKey, pubKey) async {
          await widget._tempSessionController
              .disconnectAndRemove(config.host);

          setState(() {
            config.host = host;
            config.username = user;
            config.password = pass;
            config.port = port;
          });

          if (context.mounted) {
            dialogContext.pop();
            _selectTempSession(config);
          }
        },
      ),
    );
  }
}
