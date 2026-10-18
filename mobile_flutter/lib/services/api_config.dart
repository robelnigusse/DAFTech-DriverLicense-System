/// Central API configuration.
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
///   dotnet watch --urls "http://0.0.0.0:5000"
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.8.118:5000/api',
);
