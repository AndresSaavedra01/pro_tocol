enum AppInstallStatus {
  idle,
  installing,
  success,
  failure,
}

class AppInstallState {
  final AppInstallStatus status;
  final String? message;

  const AppInstallState({
    required this.status,
    this.message,
  });

  const AppInstallState.idle()
      : status = AppInstallStatus.idle,
        message = null;

  const AppInstallState.installing([String? message])
      : status = AppInstallStatus.installing,
        message = message;

  const AppInstallState.success([String? message])
      : status = AppInstallStatus.success,
        message = message;

  const AppInstallState.failure([String? message])
      : status = AppInstallStatus.failure,
        message = message;

  bool get isBusy => status == AppInstallStatus.installing;
  bool get hasSucceeded => status == AppInstallStatus.success;
  bool get hasFailed => status == AppInstallStatus.failure;
}