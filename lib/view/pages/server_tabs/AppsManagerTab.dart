
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pro_tocol/controller/ServerAppsController.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/logic/apps_manager_catalog.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';
import 'package:pro_tocol/model/entities/Server.dart';

import '../../../model/entities/DataBaseEntities.dart';
import '../../theme/AppColors.dart';

class AppsManagerTab extends StatefulWidget {
  final ServerConfig serverConfig;
  final Server? activeServer;

  const AppsManagerTab({
    super.key,
    required this.serverConfig,
    required this.activeServer,
  });

  @override
  State<AppsManagerTab> createState() => _AppsManagerTabState();
  ServerAppsController get _appsController => getIt<ServerAppsController>();
}

class _AppsManagerTabState extends State<AppsManagerTab> {
  late final ValueListenable<Map<String, AppInstallState>> _appInstallStatesListenable;
  late final ValueListenable<List<ManagedApp>> _appsSearchResultsListenable;
  Map<String, AppInstallState> _previousAppInstallStates = const {};
  bool _appsStatusSyncRequested = false;
  bool _isAppsStatusSyncInProgress = false;
  final TextEditingController _appsSearchController = TextEditingController();
  Timer? _appsSearchDebounce;
  bool _isAppsSearchInProgress = false;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _appInstallStatesListenable = widget._appsController.installStatesListenable(widget.serverConfig.id);
    _appsSearchResultsListenable = widget._appsController.searchResultsListenable(widget.serverConfig.id);
    _previousAppInstallStates = Map<String, AppInstallState>.from(widget._appsController.getInstallStates(widget.serverConfig.id));
    _appInstallStatesListenable.addListener(_handleAppInstallStateChanged);
  }

  @override
  void dispose() {
    _appInstallStatesListenable.removeListener(_handleAppInstallStateChanged);
    _appsSearchDebounce?.cancel();
    _appsSearchController.dispose();
    super.dispose();
  }

  void _handleAppInstallStateChanged() {
    if (!mounted) return;
    final current = Map<String, AppInstallState>.from(_appInstallStatesListenable.value);
    for (final entry in current.entries) {
      final prev = _previousAppInstallStates[entry.key]?.status;
      final cur = entry.value.status;
      if (prev == cur) continue;
      final app = AppsManagerCatalog.byId(entry.key);
      final name = app?.displayName ?? entry.key;

      if (cur == AppInstallStatus.installing) _showSnackBar('$name: instalando');
      else if (cur == AppInstallStatus.uninstalling) _showSnackBar('$name: eliminando');
      else if (cur == AppInstallStatus.installed && prev == AppInstallStatus.installing) _showSnackBar('$name: instalación exitosa');
      else if (cur == AppInstallStatus.idle && prev == AppInstallStatus.uninstalling) _showSnackBar('$name: eliminación exitosa');
      else if (cur == AppInstallStatus.failure) _showSnackBar(prev == AppInstallStatus.uninstalling ? '$name: eliminación fallida' : '$name: instalación fallida', isError: true);
    }
    _previousAppInstallStates = current;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.surface));
  }

  void _handleAppsSearchChanged(String value) {
    _appsSearchDebounce?.cancel();
    _appsSearchDebounce = Timer(const Duration(milliseconds: 350), () => _runAppsSearch(value));
    setState(() {});
  }

  Future<void> _runAppsSearch(String query) async {
    final id = ++_searchRequestId;
    if (mounted) setState(() => _isAppsSearchInProgress = true);
    try {
      await widget._appsController.searchApps(serverId: widget.serverConfig.id, query: query);
    } finally {
      if (!mounted || id != _searchRequestId) return;
      setState(() => _isAppsSearchInProgress = false);
    }
  }

  void _clearAppsSearch() {
    _appsSearchController.clear();
    _appsSearchDebounce?.cancel();
    _runAppsSearch('');
    if (mounted) setState(() {});
  }

  Future<void> _syncAppsStatus() async {
    if (_isAppsStatusSyncInProgress) return;
    if (mounted) setState(() => _isAppsStatusSyncInProgress = true);
    try {
      await widget._appsController.refreshInstalledApps(serverId: widget.serverConfig.id);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isAppsStatusSyncInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_appsStatusSyncRequested) {
      _appsStatusSyncRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAppsStatus();
      });
    }

    return ValueListenableBuilder<Map<String, AppInstallState>>(
      valueListenable: _appInstallStatesListenable,
      builder: (context, states, _) {
        return ValueListenableBuilder<List<ManagedApp>>(
          valueListenable: _appsSearchResultsListenable,
          builder: (context, searchResults, __) {
            return Column(
              children: [
                if (_isAppsStatusSyncInProgress)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: AppColors.surface,
                    child: const Row(children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                      SizedBox(width: 10),
                      Text('Comprobando apps instaladas...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  color: AppColors.surface,
                  child: TextField(
                    controller: _appsSearchController,
                    onChanged: _handleAppsSearchChanged,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Buscar paquetes (git, htop, nginx...)',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                      suffixIcon: _isAppsSearchInProgress
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                          : (_appsSearchController.text.trim().isNotEmpty
                          ? IconButton(onPressed: _clearAppsSearch, icon: const Icon(Icons.close, color: AppColors.textMuted))
                          : null),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                  ),
                ),
                Expanded(
                  child: searchResults.isEmpty
                      ? const Center(child: Text('Sin resultados para tu búsqueda.', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final app = searchResults[i];
                      final state = states[app.id] ?? const AppInstallState.idle();
                      return _buildManagedAppCard(app: app, state: state);
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildManagedAppCard({required ManagedApp app, required AppInstallState state}) {
    final pkgMgr = (widget.activeServer?.packageManager ?? 'unknown').toLowerCase();
    final canRunAction = !state.isBusy && pkgMgr != 'unknown';
    final isInstalled = state.isInstalled;

    final btnLabel = state.status == AppInstallStatus.installing ? 'Instalando...'
        : state.status == AppInstallStatus.uninstalling ? 'Eliminando...'
        : isInstalled ? 'Eliminar' : 'Instalar';
    final btnColor = isInstalled ? AppColors.error : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(app.displayName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(app.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              _buildInstallStateBadge(state),
              if (state.message != null && state.message!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(state.message!, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
              if (pkgMgr == 'unknown') ...[
                const SizedBox(height: 8),
                const Text('Package manager no detectado.', style: TextStyle(color: AppColors.error, fontSize: 11)),
              ],
            ],
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: canRunAction ? () {
              if (isInstalled) {
                widget._appsController.uninstallAppInBackground(serverId: widget.serverConfig.id, appId: app.id, packageName: app.packageName);
              } else {
                widget._appsController.installAppInBackground(serverId: widget.serverConfig.id, appId: app.id, packageName: app.packageName);
              }
            } : null,
            style: ElevatedButton.styleFrom(backgroundColor: btnColor, disabledBackgroundColor: AppColors.border, foregroundColor: AppColors.textPrimary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            child: Text(btnLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallStateBadge(AppInstallState state) {
    String label; Color color;
    switch (state.status) {
      case AppInstallStatus.installing: label = 'Instalando'; color = Colors.amber; break;
      case AppInstallStatus.uninstalling: label = 'Eliminando'; color = Colors.orange; break;
      case AppInstallStatus.installed: label = 'Instalada'; color = AppColors.success; break;
      case AppInstallStatus.failure: label = 'Fallo'; color = AppColors.error; break;
      case AppInstallStatus.success: label = 'Exito'; color = AppColors.success; break;
      case AppInstallStatus.idle: label = 'Listo'; color = AppColors.textMuted; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.35))),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}