import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class IAService {
  // Pega aquí la URL que te dio Cloudflare en el Paso 2 (SIN la barra final /)
  final String baseUrl = 'https://past-subjects-courage-via.trycloudflare.com';
  
  // La credencial secreta que definimos en tu main.py de FastAPI
  final String apiKey = 'mi_super_secreto_123';

  /// Método para generar texto en modo streaming (Cumple con los Criterios de Aceptación)
  Stream<String> generateStream(String prompt) async* {
    final url = Uri.parse('$baseUrl/generar/');
    
    final request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['X-API-Key'] = apiKey
      ..body = jsonEncode({
        "pregunta": prompt,
        "modelo": "llama-3.3-70b-versatile" // El modelo ultrarrápido de Groq
      });

    final client = http.Client();

    try {
      // Manejo de tiempos de espera (Criterio de Aceptación)
      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('El servidor de IA tardó demasiado en responder.'),
      );

      // Manejo de errores de red o autenticación (Criterio de Aceptación)
      if (response.statusCode == 403) {
        throw Exception('Acceso denegado: Revisa la API Key.');
      } else if (response.statusCode != 200) {
        throw HttpException('Error del servidor: Código ${response.statusCode}');
      }

      // Procesamiento del texto en streaming
      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (var chunk in stream) {
        if (chunk.isNotEmpty) {
          final jsonResponse = jsonDecode(chunk);
          if (jsonResponse.containsKey('respuesta')) {
             yield jsonResponse['respuesta']; 
          } else if (jsonResponse.containsKey('error')) {
             throw Exception('Error desde Groq: ${jsonResponse['error']}');
          }
        }
      }
    } on SocketException {
      throw Exception('Error de red: No se pudo conectar al servidor de IA.');
    } finally {
      client.close();
    }
  }
}