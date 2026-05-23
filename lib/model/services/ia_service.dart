import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../entities/chat_message.dart';

class IAService {
  // --- CONFIGURACIÓN DE NUBE ---

  // 1. Coloca aquí la URL completa de tu servidor en la nube (sin el /generar)
  static const String _baseUrl = 'https://copyrighted-attribute-gage-spirit.trycloudflare.com';

  // 2. Tu API Key de seguridad definida en el .env del servidor
  static const String _apiKey = 'mi_super_secreto_123';

  Stream<String> generateStream(String prompt, List<ChatMessage> historial) async* {
    // Mapeamos el historial al formato que espera el Backend
    final historialMap = historial.map((m) => {
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.text,
    }).toList();

    // El endpoint final
    final url = Uri.parse('$_baseUrl/generar/');

    final request = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-API-Key': _apiKey,
      })
      ..body = jsonEncode({
        'historial': historialMap,
        'modelo': 'llama-3.3-70b-versatile', // O el que prefieras por defecto
      });

    final client = http.Client();

    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('El servidor en la nube no respondió.'),
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
          // Ignorar errores de parsing en fragmentos incompletos
          continue;
        }
      }
    } on SocketException {
      throw Exception('Error de conexión: No se pudo alcanzar el servidor en la nube.');
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
    // Inyectamos la instrucción requerida al prompt
    final String promptConContexto = "$prompt\n\n[IMPORTANTE: El script se guardará y ejecutará desde el directorio '/scripts' en el servidor. Adapta cualquier ruta relativa a este hecho.]";

    final url = Uri.parse('$_baseUrl/generar-script/');
    final request = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-API-Key': _apiKey,
      })
      ..body = jsonEncode({
        'historial': [
          {'role': 'user', 'content': promptConContexto}
        ],
        'modelo': 'llama-3.3-70b-versatile',
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