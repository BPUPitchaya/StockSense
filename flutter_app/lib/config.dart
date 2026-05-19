class Config {
  static String apiBaseUrl = 'http://localhost:8000';
  
  // Call this from main() or a settings screen to configure the URL
  static void setApiUrl(String url) {
    apiBaseUrl = url;
  }
}
