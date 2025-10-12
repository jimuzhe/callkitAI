enum AppEnvironment { dev, prod }

class AppEnvironmentConfig {
  static const String _envVar = 'APP_ENV';

  static AppEnvironment get current {
    const raw = String.fromEnvironment(_envVar, defaultValue: 'prod');
    return raw.toLowerCase() == 'dev'
        ? AppEnvironment.dev
        : AppEnvironment.prod;
  }

  static bool get isDev => current == AppEnvironment.dev;
  static bool get isProd => !isDev;
}
