import 'package:flutter_test/flutter_test.dart';
import 'package:pro_tocol/logic/apps_manager_state.dart';

void main() {
  group('AppInstallState', () {
    test('idle state is default and not busy', () {
      const state = AppInstallState.idle();

      expect(state.status, AppInstallStatus.idle);
      expect(state.message, isNull);
      expect(state.isBusy, isFalse);
      expect(state.hasSucceeded, isFalse);
      expect(state.hasFailed, isFalse);
    });

    test('installing state carries message and is busy', () {
      const state = AppInstallState.installing('Instalando git');

      expect(state.status, AppInstallStatus.installing);
      expect(state.message, 'Instalando git');
      expect(state.isBusy, isTrue);
      expect(state.hasSucceeded, isFalse);
      expect(state.hasFailed, isFalse);
    });

    test('success state is marked as succeeded', () {
      const state = AppInstallState.success('Listo');

      expect(state.status, AppInstallStatus.success);
      expect(state.message, 'Listo');
      expect(state.isBusy, isFalse);
      expect(state.hasSucceeded, isTrue);
      expect(state.hasFailed, isFalse);
    });

    test('failure state is marked as failed', () {
      const state = AppInstallState.failure('No permitido');

      expect(state.status, AppInstallStatus.failure);
      expect(state.message, 'No permitido');
      expect(state.isBusy, isFalse);
      expect(state.hasSucceeded, isFalse);
      expect(state.hasFailed, isTrue);
    });
  });
}