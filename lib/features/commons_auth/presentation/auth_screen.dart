import 'package:flutter/material.dart';
import 'package:wiki_lazy_coders/core/constants/api_constants.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/commons_auth/models/auth_state.dart';
import 'package:wiki_lazy_coders/features/commons_auth/services/wikimedia_auth_service.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;

  const AuthScreen({super.key, this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final WikimediaAuthService _authService = WikimediaAuthService();
  bool _isLoading = true;
  WikimediaUser? _currentUser;
  OAuthTokens? _currentTokens;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if deep link callback arrived
      final initialUri = await _authService.checkPendingAuthUri();
      if (initialUri != null) {
        final uri = Uri.tryParse(initialUri);
        final code = uri?.queryParameters['code'];
        if (code != null) {
          await _authService.handleAuthorizationCode(code);
        }
      }

      final tokens = await _authService.getValidTokens();
      final user = await _authService.getStoredUser();

      setState(() {
        _currentTokens = tokens;
        _currentUser = user;
        _isLoading = false;
      });

      if (tokens != null && widget.onAuthSuccess != null) {
        widget.onAuthSuccess!();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _startOAuth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.startOAuthFlow();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _handleManualCode(String code) async {
    if (code.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.handleAuthorizationCode(code);
      await _checkAuthState();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    setState(() {
      _currentTokens = null;
      _currentUser = null;
    });
  }

  void _showClientIdDialog() async {
    final currentId = await _authService.getClientId();
    final controller = TextEditingController(text: currentId);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Configure OAuth Client ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the OAuth 2.0 Client ID registered on Wikimedia Commons:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                hintText: 'wikilazycoders_app_client',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Redirect URI: ${ApiConstants.defaultRedirectUri}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _authService.setClientId(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _checkAuthState();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showManualCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Enter Authorization Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If your browser redirected with a "code=..." query parameter, paste it below:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Authorization Code',
                hintText: 'Paste code here',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleManualCode(controller.text);
            },
            child: const Text('Submit Code'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Wikimedia Connection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'OAuth Settings',
            onPressed: _showClientIdDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkAuthState,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.recordingRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.recordingRed),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppTheme.recordingRed, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_currentUser != null && _currentTokens != null)
                    _buildConnectedCard()
                  else
                    _buildDisconnectedCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildConnectedCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _currentUser!.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _currentUser!.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, color: AppTheme.primaryAccent, size: 18),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Edits: ${_currentUser!.editCount}  •  ID: ${_currentUser!.id}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32, color: AppTheme.border),
            const Text(
              'Authentication Details',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            _buildInfoRow('Provider', 'Wikimedia Commons OAuth 2.0 (PKCE)'),
            _buildInfoRow('Token Status', _currentTokens!.isExpired ? 'Expired' : 'Active & Verified'),
            _buildInfoRow('Storage', 'Android Keystore (EncryptedSharedPreferences)'),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: AppTheme.recordingRed),
              label: const Text('Disconnect Account', style: TextStyle(color: AppTheme.recordingRed)),
              onPressed: _signOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_open_rounded, size: 48, color: AppTheme.primaryAccent),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connect with Wikimedia Commons',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Authenticate securely via OAuth 2.0 authorization-code flow with PKCE. '
                  'Your Wikimedia password is never entered or stored in this application.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Wikimedia'),
                  onPressed: _startOAuth,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _showManualCodeDialog,
                  child: const Text('Have an Authorization Code? Enter manually'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: AppTheme.surfaceVariant,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppTheme.textMuted),
                    SizedBox(width: 8),
                    Text('OAuth Consumer Setup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Register a public OAuth 2.0 client on Special:OAuthConsumerRegistration/propose:\n'
                  '• Client Type: Public (Native/Mobile)\n'
                  '• Redirect URI: wikilazycoders://oauth\n'
                  '• Scopes: Basic rights & upload rights',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
