import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/repositories/AiConfigRepository.dart';
import '../entities/chat_message.dart';

class IAService {
  // --- CONFIGURACIÓN DE NUBE ---

  // 1. Coloca aquí la URL completa de tu servidor en la nube (sin el /generar)
  static const String _baseUrl = 'https://copyrighted-attribute-gage-spirit.trycloudflare.com';

  // 2. Tu API Key de seguridad definida en el .env del servidor
  static const String _apiKey = 'mi_super_secreto_123';

  final AiConfigRepository _configRepository;

  IAService(this._configRepository);

  String _getEndpointForPersonality(String personality) {
    switch (personality) {
      case 'tatiana':
        return '/chat/';
      case 'iberlina':
        return '/generar-iberlina/';
      case 'yousua':
        return '/generar-yousua/';
      default:
        return '/chat/';
    }
  }

  Stream<Map<String, dynamic>> generateStream(List<Map<String, dynamic>> historialMap, {String? contextoServidor}) async* {
    final config = await _configRepository.getConfig() ?? AiConfig();

    final request = http.Request('POST', Uri.parse('$_baseUrl${_getEndpointForPersonality(config.iaPersonality)}'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-API-Key': _apiKey,
      })
      ..body = jsonEncode({
        'historial': historialMap,
        'modelo': config.model,
        'contexto_servidor': contextoServidor, // Pasamos el contexto del servidor a la IA
      });

    final client = http.Client();

    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 40), // Aumentamos el timeout porque la IA puede tardar pensando
        onTimeout: () => throw TimeoutException('El servidor de IA no respondió.'),
      );

      if (response.statusCode != 200) {
        throw HttpException('Error del servidor: ${response.statusCode}');
      }

      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());

      await for (final line in stream) {
        if (line.isEmpty) continue;
        try {
          final jsonResponse = jsonDecode(line);
          yield jsonResponse; // Devolvemos el Map completo (puede ser texto o acción)
        } catch (e) {
          continue; // Ignorar fragmentos rotos
        }
      }
    } finally {
      client.close();
    }
  }

  // --- MÉTODOS COMPLEMENTARIOS ---

  Future<void> testConnection() async {
    // Puedes llamar a un endpoint de salud si lo tienes, o simplemente un delay
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<List<String>> fetchModels() async {
    return [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
    ];
  }

  Future<String> generarScript(String prompt) async {
    final config = await _configRepository.getConfig() ?? AiConfig();
    final token = await _configRepository.getToken();

    // Inyectamos la instrucción requerida al prompt
    final String promptConContexto = "$prompt\n\n[IMPORTANTE: El script se guardará y ejecutará desde el directorio '/scripts' en el servidor. Adapta cualquier ruta relativa a este hecho.]";

    final url = Uri.parse('$_baseUrl/generar-script/');
    final request = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-API-Key': token?.isNotEmpty == true ? token! : _apiKey,
      })
      ..body = jsonEncode({
        'historial': [
          {'role': 'user', 'content': promptConContexto}
        ],
        'modelo': config.model,
      });

    final client = http.Client();

    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('El servidor no respondió al generar el script.'),
      );

      if (response.statusCode == 403) {
        throw Exception('Error de autenticación: API Key inválida.');
      }
      if (response.statusCode != 200) {
        throw HttpException('Error del servidor: ${response.statusCode}');
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
          
      StringBuffer scriptCompleto = StringBuffer();

      await for (final line in stream) {
        if (line.isEmpty) continue;
        try {
          final jsonResponse = jsonDecode(line);
          if (jsonResponse.containsKey('respuesta')) {
            scriptCompleto.write(jsonResponse['respuesta']);
          } else if (jsonResponse.containsKey('error')) {
            throw Exception(jsonResponse['error']);
          }
        } catch (e) {
          // Ignoramos parsing en fragmentos incompletos
          continue;
        }
      }
      return scriptCompleto.toString().trim();
    } on SocketException {
      throw Exception('Error de conexión al servidor en la nube.');
    } finally {
      client.close();
    }
  }
}