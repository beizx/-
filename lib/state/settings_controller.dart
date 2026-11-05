import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/text_utils.dart';
import '../models/language.dart';
import '../models/reader_settings.dart';
import '../models/translation_provider.dart';
import '../models/tts_settings.dart';
import '../services/translation/gateway_engine.dart';
import '../services/translation/translation_engine.dart';
import '../services/translation/youdao_engine.dart';

class ApiConnectionTestResult {
  const ApiConnectionTestResult({
    required this.success,
    required this.message,
    this.preview,
    this.latency,
  });

  final bool success;
  final String message;
  final String? preview;
  final Duration? latency;

  String get latencyLabel => latency == null ? '' : formatLatency(latency!);
}

/// Persists UI preferences and keeps API keys in platform secure storage.
///
/// Keys are intentionally never written to SharedPreferences or app logs.
class SettingsController extends ChangeNotifier {
  factory SettingsController({
    required SharedPreferences preferences,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) {
    return SettingsController._(preferences, secureStorage);
  }

  SettingsController._(this._preferences, this._secureStorage);

  static const _sourceKey = 'translation.source_language';
  static const _targetKey = 'translation.target_language';
  static const _providerKey = 'translation.provider';
  static const _youdaoAppKeyStorageKey = 'youdao.app_key';
  static const _youdaoSecretStorageKey = 'youdao.app_secret';
  static const _gatewayUrlKey = 'translation.gateway_url';
  static const _gatewayTokenStorageKey = 'gateway.token';
  static const _readerFontSizeKey = 'reader.font_size';
  static const _readerLineHeightKey = 'reader.line_height';
  static const _readerSkinKey = 'reader.skin';
  static const _readerSerifKey = 'reader.serif';
  static const _readerPreferencesKey = 'reader.preferences.v2';
  static const _ttsPreferencesKey = 'tts.preferences.v1';
  static const _backgroundGuideKey = 'tts.background_guide_dismissed';
  static const _ttsWasActiveKey = 'tts.was_active';

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secureStorage;

  AppLanguage _sourceLanguage = Languages.auto;
  AppLanguage _targetLanguage = Languages.zh;
  String _providerId = TranslationProviders.youdao.id;
  String? _youdaoAppKey;
  String? _youdaoAppSecret;
  String _gatewayUrl = '';
  String? _gatewayToken;
  bool _loaded = false;
  String? _storageError;
  ReaderPreferences _reader = const ReaderPreferences();
  TtsPreferences _tts = const TtsPreferences();

  AppLanguage get sourceLanguage => _sourceLanguage;
  AppLanguage get targetLanguage => _targetLanguage;
  String get providerId => _providerId;
  TranslationProviderInfo get provider =>
      TranslationProviders.byId(_providerId);
  String? get youdaoAppKey => _youdaoAppKey;
  String? get youdaoAppSecret => _youdaoAppSecret;
  String get gatewayUrl => _gatewayUrl;
  String? get gatewayToken => _gatewayToken;
  bool get loaded => _loaded;
  String? get storageError => _storageError;
  ReaderPreferences get readerPreferences => _reader;
  TtsPreferences get ttsPreferences => _tts;

  bool get backgroundPlaybackGuideDismissed =>
      _preferences.getBool(_backgroundGuideKey) ?? false;

  /// True when the process last exited while 听书 was still playing or paused.
  bool get ttsWasActive => _preferences.getBool(_ttsWasActiveKey) ?? false;

  bool get isYoudaoConfigured =>
      (_youdaoAppKey?.trim().isNotEmpty ?? false) &&
      (_youdaoAppSecret?.trim().isNotEmpty ?? false);

  bool get isGatewayConfigured => _gatewayUrl.trim().isNotEmpty;

  bool get isCurrentProviderConfigured => switch (_providerId) {
    'gateway' => isGatewayConfigured,
    _ => isYoudaoConfigured,
  };

  /// Switches the active translation engine.
  Future<void> setProvider(String providerId) async {
    if (_providerId == providerId) return;
    _providerId = TranslationProviders.byId(providerId).id;
    await _preferences.setString(_providerKey, _providerId);
    notifyListeners();
  }

  Future<void> load() async {
    _sourceLanguage = Languages.sourceByCode(
      _preferences.getString(_sourceKey),
    );
    final storedTarget = _preferences.getString(_targetKey);
    final target = Languages.byCode(storedTarget ?? Languages.zh.code);
    _targetLanguage = target.isAuto ? Languages.zh : target;
    _providerId = _preferences.getString(_providerKey) ?? provider.id;
    _reader = _loadReaderPreferences();
    _tts = TtsPreferences.decode(_preferences.getString(_ttsPreferencesKey));
    _gatewayUrl = _preferences.getString(_gatewayUrlKey) ?? '';

    try {
      final values = await Future.wait([
        _secureStorage.read(key: _youdaoAppKeyStorageKey),
        _secureStorage.read(key: _youdaoSecretStorageKey),
        _secureStorage.read(key: _gatewayTokenStorageKey),
      ]);
      _youdaoAppKey = values[0];
      _youdaoAppSecret = values[1];
      _gatewayToken = values[2];
      _storageError = null;
    } on Object catch (error) {
      _storageError = '无法读取系统安全存储：$error';
      _youdaoAppKey = null;
      _youdaoAppSecret = null;
    }

    _loaded = true;
    notifyListeners();
  }

  ReaderPreferences _loadReaderPreferences() {
    final raw = _preferences.getString(_readerPreferencesKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return ReaderPreferences.fromJson(Map<String, Object?>.from(decoded));
        }
      } on Object {
        // Fall through to legacy keys / defaults.
      }
    }
    // v1.2 stored only font size, line height, skin and typeface.
    return ReaderPreferences(
      fontSize: (_preferences.getDouble(_readerFontSizeKey) ?? 18.0).clamp(
        ReaderPreferences.minFontSize,
        ReaderPreferences.maxFontSize,
      ),
      lineHeight: (_preferences.getDouble(_readerLineHeightKey) ?? 1.95).clamp(
        ReaderPreferences.minLineHeight,
        ReaderPreferences.maxLineHeight,
      ),
      skin: ReaderSkin.byName(_preferences.getString(_readerSkinKey)),
      typeface: (_preferences.getBool(_readerSerifKey) ?? true)
          ? ReaderTypeface.serif
          : ReaderTypeface.sans,
    ).normalized();
  }

  Future<void> setReaderPreferences(ReaderPreferences preferences) async {
    final clamped = preferences.normalized();
    _reader = clamped;
    await _preferences.setString(
      _readerPreferencesKey,
      jsonEncode(clamped.toJson()),
    );
    notifyListeners();
  }

  Future<void> resetReaderPreferences() =>
      setReaderPreferences(const ReaderPreferences());

  Future<void> dismissBackgroundPlaybackGuide() async {
    await _preferences.setBool(_backgroundGuideKey, true);
    notifyListeners();
  }

  Future<void> setTtsWasActive(bool active) async {
    if (ttsWasActive == active) return;
    await _preferences.setBool(_ttsWasActiveKey, active);
  }

  Future<void> setTtsPreferences(TtsPreferences preferences) async {
    final normalized = preferences.normalized();
    _tts = normalized;
    await _preferences.setString(_ttsPreferencesKey, normalized.encode());
    notifyListeners();
  }

  Future<void> setLanguages({AppLanguage? source, AppLanguage? target}) async {
    var changed = false;
    if (source != null && source != _sourceLanguage) {
      _sourceLanguage = source;
      changed = true;
      await _preferences.setString(_sourceKey, source.code);
    }
    if (target != null && !target.isAuto && target != _targetLanguage) {
      _targetLanguage = target;
      changed = true;
      await _preferences.setString(_targetKey, target.code);
    }
    if (changed) notifyListeners();
  }

  Future<void> saveYoudaoCredentials({
    required String appKey,
    required String appSecret,
  }) async {
    final trimmedKey = appKey.trim();
    final trimmedSecret = appSecret.trim();
    if (trimmedKey.isEmpty || trimmedSecret.isEmpty) {
      throw const FormatException('App ID 与 App Secret 都不能为空');
    }
    await _secureStorage.write(key: _youdaoAppKeyStorageKey, value: trimmedKey);
    await _secureStorage.write(
      key: _youdaoSecretStorageKey,
      value: trimmedSecret,
    );
    _youdaoAppKey = trimmedKey;
    _youdaoAppSecret = trimmedSecret;
    _providerId = TranslationProviders.youdao.id;
    await _preferences.setString(_providerKey, _providerId);
    _storageError = null;
    notifyListeners();
  }

  Future<void> clearYoudaoCredentials() async {
    await _secureStorage.delete(key: _youdaoAppKeyStorageKey);
    await _secureStorage.delete(key: _youdaoSecretStorageKey);
    _youdaoAppKey = null;
    _youdaoAppSecret = null;
    notifyListeners();
  }

  Future<void> saveGatewayConfig({required String url, String? token}) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw const FormatException('网关地址不能为空');
    }
    final uri = Uri.tryParse(
      trimmedUrl.startsWith('http') ? trimmedUrl : 'http://$trimmedUrl',
    );
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('网关地址格式不正确，例如 http://192.168.1.5:8080');
    }
    _gatewayUrl = trimmedUrl;
    _gatewayToken = (token ?? '').trim();
    await _preferences.setString(_gatewayUrlKey, trimmedUrl);
    if (_gatewayToken!.isEmpty) {
      await _secureStorage.delete(key: _gatewayTokenStorageKey);
    } else {
      await _secureStorage.write(
        key: _gatewayTokenStorageKey,
        value: _gatewayToken,
      );
    }
    _providerId = TranslationProviders.gateway.id;
    await _preferences.setString(_providerKey, _providerId);
    _storageError = null;
    notifyListeners();
  }

  Future<void> clearGatewayConfig() async {
    _gatewayUrl = '';
    _gatewayToken = null;
    await _preferences.remove(_gatewayUrlKey);
    await _secureStorage.delete(key: _gatewayTokenStorageKey);
    notifyListeners();
  }

  TranslationEngine? createEngine() {
    if (_providerId == TranslationProviders.gateway.id) {
      if (!isGatewayConfigured) return null;
      return GatewayEngine(baseUrl: _gatewayUrl, token: _gatewayToken);
    }
    if (!isYoudaoConfigured) return null;
    return YoudaoEngine(appKey: _youdaoAppKey!, appSecret: _youdaoAppSecret!);
  }

  /// Probes a gateway without saving it first.
  Future<ApiConnectionTestResult> testGatewayConnection({
    required String url,
    String? token,
  }) async {
    final engine = GatewayEngine(baseUrl: url, token: token);
    final started = DateTime.now();
    try {
      await engine.ping();
      final preview = await engine.translate(
        text: 'Hello',
        sourceLanguage: Languages.auto.code,
        targetLanguage: Languages.zh.code,
      );
      return ApiConnectionTestResult(
        success: true,
        message: '网关连接成功，已返回译文',
        preview: preview,
        latency: DateTime.now().difference(started),
      );
    } on TranslationException catch (error) {
      return ApiConnectionTestResult(
        success: false,
        message: error.message,
        latency: DateTime.now().difference(started),
      );
    } on Object catch (error) {
      return ApiConnectionTestResult(
        success: false,
        message: '连接失败：$error',
        latency: DateTime.now().difference(started),
      );
    } finally {
      engine.close();
    }
  }

  /// Tests form values without saving them first.
  Future<ApiConnectionTestResult> testYoudaoConnection({
    required String appKey,
    required String appSecret,
  }) async {
    if (appKey.trim().isEmpty || appSecret.trim().isEmpty) {
      return const ApiConnectionTestResult(
        success: false,
        message: '请先填写 App ID 与 App Secret',
      );
    }

    final engine = YoudaoEngine(
      appKey: appKey.trim(),
      appSecret: appSecret.trim(),
    );
    final started = DateTime.now();
    try {
      final preview = await engine.translate(
        text: 'Hello',
        sourceLanguage: Languages.auto.code,
        targetLanguage: Languages.zh.code,
      );
      return ApiConnectionTestResult(
        success: true,
        message: '连接成功，有道返回了译文',
        preview: preview,
        latency: DateTime.now().difference(started),
      );
    } on TranslationException catch (error) {
      return ApiConnectionTestResult(
        success: false,
        message: error.message,
        latency: DateTime.now().difference(started),
      );
    } on Object catch (error) {
      return ApiConnectionTestResult(
        success: false,
        message: '连接失败：$error',
        latency: DateTime.now().difference(started),
      );
    } finally {
      engine.close();
    }
  }
}
