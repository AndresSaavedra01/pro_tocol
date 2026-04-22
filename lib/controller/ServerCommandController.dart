
import '../logic/command_history_manager.dart';
import '../model/entities/ServerMetrics.dart';
import 'ServerConnectionController.dart';

class ServerCommandController {
  final ServerConnectionController _connectionController;
  final CommandHistoryManager _commandHistoryManager;

  ServerCommandController(this._connectionController, this._commandHistoryManager);

  CommandHistoryManager get commandHistoryManager => _commandHistoryManager;

  Future<ServerMetrics> getServerMetrics(int serverId) async {
    final server = _connectionController.getActiveServer(serverId);
    return await server.sshService.fetchMetrics();
  }

  Future<String> executeCommand(int serverId, String command) async {
    final server = _connectionController.getActiveServer(serverId);
    final result = await server.sshService.runSingleCommand(command);
    _commandHistoryManager.add(command);
    return result;
  }
}