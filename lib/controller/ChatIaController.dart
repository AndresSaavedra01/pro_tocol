import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/entities/chat_message.dart';
import 'package:pro_tocol/model/entities/chat_message_entity.dart';
import 'package:pro_tocol/model/repositories/ChatHistoryRepository.dart';
import 'package:pro_tocol/model/services/ia_service.dart';

class ChatIaPrompt {
  final String prompt;
  final String? userDisplay;
  const ChatIaPrompt(this.prompt, this.userDisplay);
}

class ChatIaController extends ChangeNotifier {
  final String serverIp;
  final String profileId;
  final Server? activeServer;

  final IAService _iaService = getIt<IAService>();
  final ChatHistoryRepository _historyRepo = getIt<ChatHistoryRepository>();

  List<ChatMessage> mensajes = [];
  final List<ChatIaPrompt> _queue = [];

  bool isSending = false;
  bool awaitingFirstChunk = false;
  bool isScriptMode = false;

  ChatIaController({
    required this.serverIp,
    required this.profileId,
    this.activeServer,
  });

  // ================= ESTADO Y CONFIGURACIÓN =================

  void toggleScriptMode(bool value) {
    if (isSending) return;
    isScriptMode = value;
    notifyListeners();
  }

  Future<void> cargarHistorial() async {
    final mensajesDb = await _historyRepo.getMessagesByServerAndProfile(serverIp, profileId);
    if (mensajesDb.isEmpty) {
      mensajes = [
        ChatMessage(
          text: "¡Hola! Soy tu asistente de Pro-Tocol. ¿En qué te puedo ayudar con el servidor $serverIp?",
          isUser: false,
        )
      ];
    } else {
      mensajes = mensajesDb.map((e) => ChatMessage(
          text: e.editedContent ?? e.content,
          isUser: e.role == 'user'
      )).toList();
    }
    notifyListeners();
  }

  // ================= MANEJO DE MENSAJES =================

  void submitPrompt(String prompt, {String? userDisplay}) {
    _queue.add(ChatIaPrompt(prompt, userDisplay));
    _drainExternalQueue();
  }

  Future<void> enviarMensajeUsuario(String textoUsuario, {Function(String)? onScriptGenerated, Function(Object)? onError}) async {
    if (isSending || textoUsuario.isEmpty) return;

    await _saveMessageToDb('user', textoUsuario);
    mensajes.add(ChatMessage(text: textoUsuario, isUser: true));
    isSending = true;
    notifyListeners();

    if (isScriptMode) {
      await _handleScriptGeneration(textoUsuario, onScriptGenerated);
    } else {
      await _handleNormalChat(textoUsuario, onError);
    }
  }

  void _drainExternalQueue() {
    if (isSending || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    enviarMensajeUsuario(next.prompt);
  }

  // ================= LÓGICA DE IA AGÉNTICA =================

  Future<void> _handleNormalChat(String prompt, Function(Object)? onError) async {
    // 1. Construimos el historial exclusivo para la API (Independiente de la UI)
    // SOLUCIÓN: Usar <String, dynamic> para permitir listas anidadas luego
    List<Map<String, dynamic>> apiHistory = mensajes
        .where((m) => m.text.isNotEmpty)
        .map((m) => <String, dynamic>{
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.text
    })
        .toList();

    // El mensaje actual del usuario
    apiHistory.add(<String, dynamic>{'role': 'user', 'content': prompt});

    // Añadimos burbuja de carga a la UI
    mensajes.add(ChatMessage(text: '', isUser: false));
    awaitingFirstChunk = true;
    notifyListeners();

    int aiIndex = mensajes.length - 1;

    // 2. Preparamos el contexto del servidor (si está conectado)
    String? contextoServidor;
    if (activeServer != null) {
      contextoServidor = "IP: ${activeServer!.config.host}, Usuario: ${activeServer!.config.username}, "
          "Distro: ${activeServer!.distroName}";
    }

    // 3. Iniciamos el ciclo de conexión
    await _processAgenticStream(aiIndex, apiHistory, contextoServidor, onError);
  }

  // Función recursiva que intercepta los comandos, los ejecuta y le responde a la IA
  Future<void> _processAgenticStream(int aiIndex, List<Map<String, dynamic>> apiHistory, String? contextoServidor, Function(Object)? onError) async {
    final buffer = StringBuffer();
    bool isToolCall = false;
    String? commandToRun;
    String? toolCallId;

    try {
      await for (final chunk in _iaService.generateStream(apiHistory, contextoServidor: contextoServidor)) {

        // INTERCEPTOR: La IA decidió usar la terminal
        if (chunk.containsKey('tipo') && chunk['tipo'] == 'ACCION_REQUERIDA') {
          isToolCall = true;
          commandToRun = chunk['comando'];
          toolCallId = chunk['tool_call_id'];
          break; // Cortamos este stream para actuar inmediatamente
        }

        // TEXTO NORMAL: La IA está hablando / respondiendo
        if (chunk.containsKey('respuesta')) {
          buffer.write(chunk['respuesta']);
          awaitingFirstChunk = false;
          mensajes[aiIndex] = ChatMessage(text: buffer.toString(), isUser: false);
          notifyListeners();
        } else if (chunk.containsKey('error')) {
          throw Exception(chunk['error']);
        }
      }

      // CASO A: SI LA IA PIDIÓ UN COMANDO, LO EJECUTAMOS
      if (isToolCall && commandToRun != null) {

        mensajes[aiIndex] = ChatMessage(text: "🔍 Ejecutando: $commandToRun...", isUser: false);
        notifyListeners();

        String toolResult = "";
        try {
          final sshService = activeServer?.sshService;

          if (sshService != null && sshService.isConnected) {
            String cmd = commandToRun!.trim();

            // Interceptamos comandos sudo
            if (cmd.startsWith("sudo ")) {
              final password = sshService.config?.password;
              if (password != null && password.isNotEmpty) {
                final cmdWithoutSudo = cmd.substring(5).trim();
                toolResult = await sshService.runSudoCommand(cmdWithoutSudo, password);
              } else {
                toolResult = "Error de permisos: El comando requiere 'sudo', pero no hay una contraseña guardada.";
              }
            } else {
              toolResult = await sshService.runSingleCommand(cmd);
            }

            if (toolResult.isEmpty) {
              toolResult = "El comando se ejecutó pero no devolvió ninguna salida (stdout vacío).";
            }
          } else {
            toolResult = "Error: El servidor SSH no está conectado.";
          }
        } catch (e) {
          toolResult = "Error al ejecutar el comando: $e";
        }

        // --- ACTUALIZAR EL HISTORIAL DE LA API PARA LA SIGUIENTE VUELTA ---
        apiHistory.add(<String, dynamic>{
          "role": "assistant",
          "content": null,
          "tool_calls": [
            {
              "id": toolCallId,
              "type": "function",
              "function": {"name": "ejecutar_comando_ssh", "arguments": "{\"comando\": \"$commandToRun\"}"}
            }
          ]
        });

        apiHistory.add(<String, dynamic>{
          "role": "tool",
          "tool_call_id": toolCallId,
          "content": toolResult
        });

        mensajes[aiIndex] = ChatMessage(text: "🧠 Analizando resultados...", isUser: false);
        notifyListeners();

        // Llamada recursiva: Volvemos a enviar todo el historial con el resultado del comando a la IA
        await _processAgenticStream(aiIndex, apiHistory, contextoServidor, onError);
        return; // Salimos de esta iteración de la pila

      } else {
        // CASO B: EL STREAM TERMINÓ NORMALMENTE (Sin llamadas a comandos)
        // Esto significa que la IA ya terminó de razonar y esta es su respuesta final de texto.
        if (buffer.isNotEmpty) {
          await _saveMessageToDb('assistant', buffer.toString());
        }
      }

    } catch (e) {
      final errorText = 'No se pudo obtener respuesta: $e';
      awaitingFirstChunk = false;
      mensajes[aiIndex] = ChatMessage(text: errorText, isUser: false);
      if (onError != null) onError(e);
    } finally {
      if (!isToolCall) {
        isSending = false;
        awaitingFirstChunk = false;
        notifyListeners();
        _drainExternalQueue();
      }
    }
  }

  // ================= GENERACIÓN DE SCRIPTS =================

  Future<void> _handleScriptGeneration(String prompt, Function(String)? onScriptGenerated) async {
    awaitingFirstChunk = true;
    mensajes.add(ChatMessage(text: '', isUser: false));
    notifyListeners();

    final aiIndex = mensajes.length - 1;

    try {
      final scriptCode = await _iaService.generarScript(prompt);
      final assistantText = "He generado tu script:\n\n```bash\n$scriptCode\n```";

      await _saveMessageToDb('assistant', assistantText);
      awaitingFirstChunk = false;
      mensajes[aiIndex] = ChatMessage(text: assistantText, isUser: false);

      if (onScriptGenerated != null) onScriptGenerated(scriptCode);
    } catch (e) {
      final errorText = "Error al generar script: $e";
      await _saveMessageToDb('assistant', errorText);
      awaitingFirstChunk = false;
      mensajes[aiIndex] = ChatMessage(text: errorText, isUser: false);
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  // ================= LÓGICA DE SERVIDOR (SSH) =================

  Future<void> executeScriptOnServer(String scriptCode, String password) async {
    if (activeServer?.sshService == null || activeServer!.sshService!.sftp == null) {
      await _addSystemMessage("Error: No hay conexión SSH/SFTP activa con el servidor.");
      return;
    }

    isSending = true;
    notifyListeners();
    await _addSystemMessage("Iniciando despliegue y ejecución del script en /tmp/scripts...");

    try {
      final sftp = activeServer!.sshService!.sftp!;
      final ssh = activeServer!.sshService!;

      await ssh.runSingleCommand("mkdir -p /tmp/scripts");

      final tempDir = await getTemporaryDirectory();
      final fileName = "auto_${DateTime.now().millisecondsSinceEpoch}.sh";
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(scriptCode);

      final remotePath = "/tmp/scripts/$fileName";
      await sftp.uploadFile(tempFile.path, remotePath);
      await ssh.runSingleCommand("sed -i 's/\\r\$//' $remotePath && chmod +x $remotePath");

      final resultado = await ssh.runSudoCommand(remotePath, password);
      await _addSystemMessage("Ejecución Finalizada.\n\nSalida del terminal:\n```text\n$resultado\n```");

      if (await tempFile.exists()) await tempFile.delete();
    } catch (e) {
      await _addSystemMessage("Error durante la ejecución del script:\n$e");
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  // ================= UTILIDADES DE DB =================

  Future<void> _saveMessageToDb(String role, String content) async {
    await _historyRepo.saveMessage(ChatMessageEntity(
      serverIp: serverIp,
      profileId: profileId,
      role: role,
      content: content,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _addSystemMessage(String text) async {
    await _saveMessageToDb('assistant', text);
    mensajes.add(ChatMessage(text: text, isUser: false));
    notifyListeners();
  }

  Future<void> deleteAllChat() async {
    await _historyRepo.deleteAllByServerAndProfile(serverIp, profileId);
    await cargarHistorial();
  }

  Future<void> updateMessageContent(String oldText, String newText, int index) async {
    final mensajesDb = await _historyRepo.getMessagesByServerAndProfile(serverIp, profileId);
    for (final entity in mensajesDb) {
      final display = entity.editedContent ?? entity.content;
      if (entity.role == 'user' && display == oldText) {
        await _historyRepo.updateMessageContent(entity.id, newText);
        mensajes[index] = ChatMessage(text: newText, isUser: true);
        notifyListeners();
        break;
      }
    }
  }

  Future<void> deleteMessage(String text) async {
    final mensajesDb = await _historyRepo.getMessagesByServerAndProfile(serverIp, profileId);
    for (final entity in mensajesDb) {
      if (entity.role == 'user' && (entity.editedContent ?? entity.content) == text) {
        await _historyRepo.deleteMessage(entity.id);
        mensajes.removeWhere((m) => m.text == text && m.isUser);
        notifyListeners();
        break;
      }
    }
  }
}