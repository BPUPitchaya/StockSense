class Config {
  static String apiBaseUrl = 'https://stocksense-h0n6.onrender.com';
  
  // Call this from main() or a settings screen to configure the URL
  static void setApiUrl(String url) {
    apiBaseUrl = url;
  }
}
