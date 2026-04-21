class CommandHistoryManager {
  static const int _maxHistorySize = 50;

  final List<String> _history = [];
  int _currentIndex = -1;

  /// Agrega un comando al historial.
  ///
  /// Si el historial supera el tamaño máximo, se descarta el comando más antiguo.
  void add(String command) {
    final trimmedCommand = command.trim();
    if (trimmedCommand.isEmpty) return;

    // Evitar duplicados consecutivos inmediatos.
    if (_history.isNotEmpty && _history.last == trimmedCommand) {
      _resetIndex();
      return;
    }

    if (_history.length >= _maxHistorySize) {
      _history.removeAt(0);
    }
    _history.add(trimmedCommand);
    _resetIndex();
  }

  /// Retorna el comando anterior en el historial.
  ///
  /// Si ya estamos al principio, devuelve el primer comando disponible.
  String? previous() {
    if (_history.isEmpty) return null;

    if (_currentIndex <= 0) {
      _currentIndex = 0;
      return _history.first;
    }

    _currentIndex--;
    return _history[_currentIndex];
  }

  /// Retorna el siguiente comando en el historial.
  ///
  /// Si ya estamos al final, devuelve el último comando disponible.
  String? next() {
    if (_history.isEmpty) return null;

    if (_currentIndex >= _history.length - 1) {
      _currentIndex = _history.length - 1;
      return _history.last;
    }

    _currentIndex++;
    return _history[_currentIndex];
  }

  /// Limpia todo el historial de comandos.
  void clear() {
    _history.clear();
    _resetIndex();
  }

  /// Retorna la lista completa de comandos guardados.
  List<String> getHistory() => List.unmodifiable(_history);

  void _resetIndex() {
    _currentIndex = _history.length;
  }
}
