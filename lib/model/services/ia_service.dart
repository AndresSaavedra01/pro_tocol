import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/repositories/AiConfigRepository.dart';

class IAService {
  static const String defaultGroqToken =
      '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';

  final AiConfigRepository _configRepository;

  IAService(this._configRepository);

  Future<void> testConnection() async {
    final config = await _requireConfig();
    final token = await _resolveToken(config, allowFallback: true);

    final client = http.Client();
    try {
      final response = await client
          .get(
            _buildModelsUri(config),
            headers: _buildHeaders(token),
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException('Tiempo de espera agotado.'),
          );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Acceso denegado: revisa el token.');
      }
      if (response.statusCode != 200) {
        throw HttpException('Error del servidor: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Error de red: no se pudo conectar al proveedor.');
    } finally {
      client.close();
    }
  }

  Future<List<String>> fetchModels() async {
    final config = await _requireConfig();
    final token = await _resolveToken(config, allowFallback: true);

    final client = http.Client();
    try {
      final response = await client
          .get(
            _buildModelsUri(config),
            headers: _buildHeaders(token),
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException('Tiempo de espera agotado.'),
          );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Acceso denegado: revisa el token.');
      }
      if (response.statusCode != 200) {
        throw HttpException('Error del servidor: ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (_isGroq(config)) {
        final data = (body['data'] as List<dynamic>? ?? const []);
        return data
            .map((item) => item['id']?.toString())
            .whereType<String>()
            .toList();
      }

      final models = (body['models'] as List<dynamic>? ?? const []);
      return models
          .map((item) => item['name']?.toString())
          .whereType<String>()
          .toList();
    } on SocketException {
      throw Exception('Error de red: no se pudo conectar al proveedor.');
    } finally {
      client.close();
    }
  }

  Stream<String> generateStream(String prompt) async* {
    final config = await _requireConfig();
    final token = await _resolveToken(config, allowFallback: false);

    if (_isGroq(config)) {
      if (token == null || token.isEmpty) {
        throw Exception('Token requerido para Groq.');
      }
      if (config.model.trim().isEmpty) {
        throw Exception('Selecciona un modelo para Groq.');
      }

      yield* _generateGroqStream(prompt, config, token);
      return;
    }

    final url = _buildOllamaUri(config, 'api/generate');
    final request = http.Request('POST', url)
      ..headers.addAll(_buildHeaders(token))
      ..body = jsonEncode({
        'prompt': prompt,
        'model': config.model,
        'stream': true,
      });

    final client = http.Client();

    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('El servidor de IA tardo demasiado.'),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Acceso denegado: revisa el token.');
      }
      if (response.statusCode != 200) {
        throw HttpException('Error del servidor: Codigo ${response.statusCode}');
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final chunk in stream) {
        if (chunk.isEmpty) continue;
        final jsonResponse = jsonDecode(chunk);
        if (jsonResponse.containsKey('response')) {
          yield jsonResponse['response'];
        } else if (jsonResponse.containsKey('error')) {
          throw Exception('Error del proveedor: ${jsonResponse['error']}');
        }
      }
    } on SocketException {
      throw Exception('Error de red: no se pudo conectar al proveedor.');
    } finally {
      client.close();
    }
  }

  Future<AiConfig> _requireConfig() async {
    final config = await _configRepository.getConfig();
    if (config == null) {
      throw Exception('No hay configuracion de IA guardada.');
    }
    return config;
  }

  Future<String?> _resolveToken(AiConfig config, {required bool allowFallback}) async {
    final stored = await _configRepository.getToken();
    if (allowFallback && _isGroq(config) && (stored == null || stored.isEmpty)) {
      return defaultGroqToken;
    }
    return stored;
  }

  Map<String, String> _buildHeaders(String? token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _buildModelsUri(AiConfig config) {
    if (_isGroq(config)) {
      return _buildGroqUri(config, 'models');
    }
    return _buildOllamaUri(config, 'api/tags');
  }

  Uri _buildGroqUri(AiConfig config, String path) {
    final host = config.host.trim().isEmpty ? 'api.groq.com' : config.host.trim();
    final port = config.port == 443 ? null : config.port;
    return Uri(
      scheme: 'https',
      host: host,
      port: port,
      path: 'openai/v1/$path',
    );
  }

  Uri _buildOllamaUri(AiConfig config, String path) {
    final host = config.host.trim().isEmpty ? '127.0.0.1' : config.host.trim();
    return Uri(
      scheme: 'http',
      host: host,
      port: config.port,
      path: path,
    );
  }

  bool _isGroq(AiConfig config) => config.provider.toLowerCase() == 'groq';

  Stream<String> _generateGroqStream(String prompt, AiConfig config, String token) async* {
    final uri = _buildGroqUri(config, 'chat/completions');
    final request = http.Request('POST', uri)
      ..headers.addAll(_buildHeaders(token))
      ..body = jsonEncode({
        'model': config.model,
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'stream': true,
      });

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('El servidor de IA tardo demasiado.'),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Acceso denegado: revisa el token.');
      }
      if (response.statusCode != 200) {
        throw HttpException('Error del servidor: Codigo ${response.statusCode}');
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        final payload = jsonDecode(data) as Map<String, dynamic>;
        final choices = payload['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices.first['delta'] as Map<String, dynamic>?;
        final content = delta?['content']?.toString();
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      }
    } on SocketException {
      throw Exception('Error de red: no se pudo conectar al proveedor.');
    } finally {
      client.close();
    }
  }
}
