import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/text_utils.dart';
import '../models/language.dart';
import '../models/reader_settings.dart';
import '../models/translation_provider.dart';
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
  static const _readerFontSizeKey = 'reader.font_size';
  static const _readerLineHeightKey = 'reader.line_height';
  static const _readerSkinKey = 'reader.skin';
  static const _readerSerifKey = 'reader.serif';
  static const _readerPreferencesKey = 'reader.preferences.v2';

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secureStorage;

  AppLanguage _sourceLanguage = Languages.auto;
  AppLanguage _targetLanguage = Languages.zh;
  String _providerId = TranslationProviders.youdao.id;
  String? _youdaoAppKey;
  String? _youdaoAppSecret;
  bool _loaded = false;
  String? _storageError;
  ReaderPreferences _reader = const ReaderPreferences();

  AppLanguage get sourceLanguage => _sourceLanguage;
  AppLanguage get targetLanguage => _targetLanguage;
  String get providerId => _providerId;
  TranslationProviderInfo get provider =>
      TranslationProviders.byId(_providerId);
  String? get youdaoAppKey => _youdaoAppKey;
  String? get youdaoAppSecret => _youdaoAppSecret;
  bool get loaded => _loaded;
  String? get storageError => _storageError;
  ReaderPreferences get readerPreferences => _reader;

  bool get isYoudaoConfigured =>
      (_youdaoAppKey?.trim().isNotEmpty ?? false) &&
      (_youdaoAppSecret?.trim().isNotEmpty ?? false);

  bool get isCurrentProviderConfigured => isYoudaoConfigured;

  Future<void> load() async {
    _sourceLanguage = Languages.sourceByCode(
      _preferences.getString(_sourceKey),
    );
    final storedTarget = _preferences.getString(_targetKey);
    final target = Languages.byCode(storedTarget ?? Languages.zh.code);
    _targetLanguage = target.isAuto ? Languages.zh : target;
    _providerId = _preferences.getString(_providerKey) ?? provider.id;
    _reader = _loadReaderPreferences();

    try {
      final values = await Future.wait([
        _secureStorage.read(key: _youdaoAppKeyStorageKey),
        _secureStorage.read(key: _youdaoSecretStorageKey),
      ]);
      _youdaoAppKey = values[0];
      _youdaoAppSecret = values[1];
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
      serif: _preferences.getBool(_readerSerifKey) ?? true,
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

  TranslationEngine? createEngine() {
    if (!isYoudaoConfigured) return null;
    return YoudaoEngine(appKey: _youdaoAppKey!, appSecret: _youdaoAppSecret!);
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
