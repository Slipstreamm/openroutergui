import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

class DiscordOAuthService {
  // Discord OAuth2 constants
  static const String clientId = '1360717457852993576';
  // New redirect URI using the /api endpoint
  static const String redirectUri = 'https://slipstreamm.dev/api/auth';

  // Old redirect URI for backward compatibility
  static const String oldRedirectUri = 'https://slipstreamm.dev/discordapi/auth';
  static const String discordApiUrl = 'https://discord.com/api';
  static const String tokenEndpoint = '$discordApiUrl/oauth2/token';
  static const String userEndpoint = '$discordApiUrl/users/@me';

  // Storage keys
  static const String accessTokenKey = 'discord_access_token';
  static const String refreshTokenKey = 'discord_refresh_token';
  static const String tokenExpiryKey = 'discord_token_expiry';
  static const String userIdKey = 'discord_user_id';
  static const String usernameKey = 'discord_username';
  static const String codeVerifierKey = 'discord_code_verifier';

  // OAuth state
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _userId;
  String? _username;

  // Getters for user info
  String? get userId => _userId;
  String? get username => _username;
  bool get isLoggedIn => _accessToken != null && _userId != null;

  // Initialize the service by loading saved tokens
  Future<void> initialize() async {
    await _loadTokens();

    // Check if token is expired and refresh if needed
    if (_accessToken != null && _tokenExpiry != null) {
      if (_tokenExpiry!.isBefore(DateTime.now())) {
        await refreshToken();
      }
    }
  }

  // Generate a random string for security
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // Generate a random state string for security
  String _generateRandomState() {
    return _generateRandomString(32);
  }

  // Generate a code verifier for PKCE
  String _generateCodeVerifier() {
    return _generateRandomString(128); // Between 43 and 128 chars
  }

  // Generate a code challenge from the code verifier
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url
        .encode(digest.bytes)
        .replaceAll('=', '') // Remove padding
        .replaceAll('+', '-')
        .replaceAll('/', '_');
  }

  // Show a dialog to get the authorization code
  Future<String?> _showAuthCodeInputDialog(BuildContext context) async {
    final controller = TextEditingController();
    final navigatorContext = context;
    return showDialog<String>(
      context: navigatorContext,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Enter Discord Authorization Code'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('After authorizing in Discord, you will be redirected to a page with a URL like:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                    child: const Text('http://localhost:8591/callback?code=ABCDEF123456&state=...'),
                  ),
                  const SizedBox(height: 16),
                  const Text('1. Copy the code value (the part after "?code=" and before any "&")', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  const Text('2. Paste it in the field below', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Authorization Code',
                      hintText: 'e.g., ABCDEF123456',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.code),
                    ),
                    autofocus: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(null), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Submit')),
            ],
          ),
    );
  }

  // Start the OAuth flow
  Future<bool> login(BuildContext context) async {
    try {
      // Store the context for later use
      final authContext = context;

      // Generate a random state for security
      final state = _generateRandomState();

      // Generate code verifier and challenge for PKCE
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      // Save the code verifier for later use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(codeVerifierKey, codeVerifier);

      // Define the authorization URL with required scopes
      // We need identify scope to get user info
      final authUrl = Uri.https('discord.com', '/api/oauth2/authorize', {
        'client_id': clientId,
        'redirect_uri': redirectUri, // Use the new redirect URI
        'response_type': 'code',
        'scope': 'identify',
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      });

      debugPrint('Using redirect URI: $redirectUri');

      // Launch the browser for authentication with platform-specific handling
      bool launchSuccess = false;
      try {
        // Try using the standard launchUrl method first
        launchSuccess = await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Error launching URL with standard method: $e');
        // If that fails, try the string-based method as a fallback
        try {
          launchSuccess = await launchUrlString(authUrl.toString(), mode: LaunchMode.externalApplication);
        } catch (e2) {
          debugPrint('Error launching URL with string method: $e2');
          // As a last resort, try with platform default
          try {
            launchSuccess = await launchUrlString(authUrl.toString());
          } catch (e3) {
            debugPrint('All URL launch methods failed: $e3');
          }
        }
      }

      if (!launchSuccess) {
        // Show a dialog with the URL for manual copying
        if (authContext.mounted) {
          await showDialog(
            context: authContext,
            builder:
                (context) => AlertDialog(
                  title: const Text('Cannot Open Browser'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Please copy this URL and open it in your browser:'),
                      const SizedBox(height: 10),
                      SelectableText(authUrl.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
                ),
          );
        }
      }

      // Show a dialog to get the authorization code
      String? code;
      // Use a separate function to handle the dialog to avoid BuildContext issues
      if (authContext.mounted) {
        code = await _showAuthCodeInputDialog(authContext);
      } else {
        return false;
      }

      if (code == null || code.isEmpty) {
        debugPrint('No authorization code received');
        return false;
      }

      // Get the code verifier
      final prefsForVerifier = await SharedPreferences.getInstance();
      final savedCodeVerifier = prefsForVerifier.getString(codeVerifierKey);

      if (savedCodeVerifier == null) {
        debugPrint('No code verifier found');
        return false;
      }

      // Exchange the code for an access token
      // Try with the new redirect URI first
      var tokenResponse = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'client_id': clientId, 'grant_type': 'authorization_code', 'code': code, 'redirect_uri': redirectUri, 'code_verifier': savedCodeVerifier},
      );

      // If that fails, try with the old redirect URI
      if (tokenResponse.statusCode != 200) {
        debugPrint('Failed to get token with new redirect URI: ${tokenResponse.body}');
        debugPrint('Trying with old redirect URI: $oldRedirectUri');

        tokenResponse = await http.post(
          Uri.parse(tokenEndpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'client_id': clientId, 'grant_type': 'authorization_code', 'code': code, 'redirect_uri': oldRedirectUri, 'code_verifier': savedCodeVerifier},
        );
      }

      // Clear the code verifier after use
      await prefsForVerifier.remove(codeVerifierKey);

      if (tokenResponse.statusCode != 200) {
        debugPrint('Failed to get token: ${tokenResponse.body}');
        return false;
      }

      // Parse the token response
      final tokenData = jsonDecode(tokenResponse.body);
      _accessToken = tokenData['access_token'];
      _refreshToken = tokenData['refresh_token'];
      _tokenExpiry = DateTime.now().add(Duration(seconds: tokenData['expires_in']));

      // Save the tokens
      await _saveTokens();

      // Get user info
      await _fetchUserInfo();

      return isLoggedIn;
    } catch (e) {
      debugPrint('Error during login: $e');
      return false;
    }
  }

  // Refresh the access token
  Future<bool> refreshToken() async {
    if (_refreshToken == null) {
      debugPrint('No refresh token available');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'client_secret': '', // Client secret is not needed for public clients
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        },
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to refresh token: ${response.body}');
        return false;
      }

      final tokenData = jsonDecode(response.body);
      _accessToken = tokenData['access_token'];
      _refreshToken = tokenData['refresh_token'];
      _tokenExpiry = DateTime.now().add(Duration(seconds: tokenData['expires_in']));

      await _saveTokens();
      return true;
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      return false;
    }
  }

  // Fetch user information from Discord
  Future<void> _fetchUserInfo() async {
    if (_accessToken == null) {
      debugPrint('No access token available');
      return;
    }

    try {
      final response = await http.get(Uri.parse(userEndpoint), headers: {'Authorization': 'Bearer $_accessToken'});

      if (response.statusCode != 200) {
        debugPrint('Failed to get user info: ${response.body}');
        return;
      }

      final userData = jsonDecode(response.body);
      _userId = userData['id'];
      _username = userData['username'];

      // Save user info
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(userIdKey, _userId!);
      await prefs.setString(usernameKey, _username!);

      debugPrint('User logged in: $_username (ID: $_userId)');
    } catch (e) {
      debugPrint('Error fetching user info: $e');
    }
  }

  // Log out the user
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _userId = null;
    _username = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(accessTokenKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(tokenExpiryKey);
    await prefs.remove(userIdKey);
    await prefs.remove(usernameKey);

    debugPrint('User logged out');
  }

  // Load tokens from SharedPreferences
  Future<void> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(accessTokenKey);
    _refreshToken = prefs.getString(refreshTokenKey);

    final expiryMillis = prefs.getInt(tokenExpiryKey);
    if (expiryMillis != null) {
      _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMillis);
    }

    _userId = prefs.getString(userIdKey);
    _username = prefs.getString(usernameKey);

    debugPrint('Loaded tokens: ${_accessToken != null ? 'Access token available' : 'No access token'}');
  }

  // Save tokens to SharedPreferences
  Future<void> _saveTokens() async {
    if (_accessToken == null || _refreshToken == null || _tokenExpiry == null) {
      debugPrint('Cannot save tokens: Some tokens are null');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, _accessToken!);
    await prefs.setString(refreshTokenKey, _refreshToken!);
    await prefs.setInt(tokenExpiryKey, _tokenExpiry!.millisecondsSinceEpoch);

    debugPrint('Tokens saved');
  }

  // Get the authorization header for API requests
  String? getAuthHeader() {
    if (_accessToken == null) return null;
    return 'Bearer $_accessToken';
  }
}
