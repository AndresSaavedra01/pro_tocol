import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/repositories/AiConfigRepository.dart';

import '../entities/chat_message.dart';

class IAService {
  // --- CONFIGURACIÓN DE DESARROLLO (Tu ".env") ---

  // 1. CAMBIA ESTO A 'true' para ignorar la configuración guardada en la base de datos
  static const bool _useOnlyDevSettings = true;

  // 2. Coloca aquí los datos de tu servidor FastAPI
  static const String _devHost = '192.168.18.16'; // O '10.0.2.2' si usas emulador Android
  static const int _devPort = 8000;
  static const String _devApiKey = 'mi_super_secreto_123';

  final AiConfigRepository _configRepository;

  IAService(this._configRepository);

  Stream<String> generateStream(String prompt, List<ChatMessage> historial) async* {
    String host;
    int port;
    String token;
    String model;

    if (_useOnlyDevSettings) {
      host = _devHost;
      port = _devPort;
      token = _devApiKey;
      model = 'llama-3.3-70b-versatile';
    } else {
      final savedConfig = await _configRepository.getConfig();
      final savedToken = await _configRepository.getToken();

      host = (savedConfig != null && savedConfig.host.trim().isNotEmpty)
          ? savedConfig.host.trim()
          : _devHost;

      port = (savedConfig != null && savedConfig.port != 0)
          ? savedConfig.port
          : _devPort;

      token = (savedToken != null && savedToken.isNotEmpty)
          ? savedToken
          : _devApiKey;

      model = (savedConfig != null && savedConfig.model.isNotEmpty)
          ? savedConfig.model
          : 'llama-3.3-70b-versatile';
    }

    // --- CONSTRUCCIÓN DEL HISTORIAL PARA EL BACKEND ---
    // Mapeamos los mensajes de la UI al formato {'role': ..., 'content': ...}
    final historialMap = historial.map((m) => {
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.text,
    }).toList();

    final url = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/generar/',
    );

    final request = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-API-Key': token,
      })
      ..body = jsonEncode({
        'historial': historialMap, // Enviamos toda la conversación
        'modelo': model,
      });

    final client = http.Client();

    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('El servidor FastAPI no respondió.'),
      );

      if (response.statusCode == 403) {
        throw Exception('Token inválido en el servidor.');
      }
      if (response.statusCode != 200) {
        throw HttpException('Error ${response.statusCode}: ${response.reasonPhrase}');
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.isEmpty) continue;
        try {
          final jsonResponse = jsonDecode(line);
          if (jsonResponse.containsKey('respuesta')) {
            yield jsonResponse['respuesta'].toString();
          } else if (jsonResponse.containsKey('error')) {
            throw Exception(jsonResponse['error']);
          }
        } catch (e) {
          continue;
        }
      }
    } on SocketException {
      throw Exception('Error de red: No se pudo conectar a $host:$port.');
    } finally {
      client.close();
    }
  }

  // --- MÉTODOS COMPLEMENTARIOS ---

  Future<void> testConnection() async {
    // Para simplificar el test en la UI
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<List<String>> fetchModels() async {
    return [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
    ];
  }
}