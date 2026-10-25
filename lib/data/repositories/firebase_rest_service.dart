import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../core/secrets.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Firebase REST Service
//  Firestore + Firebase Auth (email/password) عبر HTTP REST
//  يعمل على Windows و Android بدون C++ SDK
//
//  الأمان: كل طلب بيتبعت بتوكن المستخدم الحقيقى (مفيش anonymous auth)،
//  وقواعد Firestore (firestore.rules) هى اللى بتفرض الصلاحيات فى السيرفر.
// ─────────────────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  const ApiException(this.status, this.code, this.message);

  bool get isPermissionDenied => status == 403;
  bool get isNotFound => status == 404;
  bool get isUnauthenticated => status == 401;

  @override
  String toString() => message;
}

/// عملية كتابة داخل batch (commit) — الـ batch ذرّى: يا كله يتنفذ يا ولا حاجة.
class WriteOp {
  final String path;
  final Map<String, dynamic> data;
  final List<String> serverTimeFields;
  final bool _merge;
  final bool _createOnly;
  final bool _delete;

  /// كتابة مستند كامل (بتستبدل الموجود). createOnly=true يفشل لو المستند موجود.
  const WriteOp.set(this.path, this.data,
      {this.serverTimeFields = const [], bool createOnly = false})
      : _merge = false,
        _createOnly = createOnly,
        _delete = false;

  /// تعديل حقول معيّنة فى مستند موجود (يفشل لو المستند مش موجود).
  const WriteOp.update(this.path, this.data,
      {this.serverTimeFields = const []})
      : _merge = true,
        _createOnly = false,
        _delete = false;

  const WriteOp.delete(this.path)
      : data = const {},
        serverTimeFields = const [],
        _merge = false,
        _createOnly = false,
        _delete = true;
}

class FirebaseRestService {
  FirebaseRestService._();
  static final instance = FirebaseRestService._();

  // القيم دي جاية من lib/core/secrets.dart (مش بيترفع على GitHub)
  static const _apiKey = Secrets.firebaseApiKey;
  static const _projectId = Secrets.firebaseProjectId;

  static const _dbName = 'projects/$_projectId/databases/(default)/documents';
  static const _firestoreBase = 'https://firestore.googleapis.com/v1/$_dbName';
  static const _commitUrl =
      'https://firestore.googleapis.com/v1/$_dbName:commit';
  static const _queryUrl =
      'https://firestore.googleapis.com/v1/$_dbName:runQuery';
  static const _authBase = 'https://identitytoolkit.googleapis.com/v1/accounts';
  static const _tokenUrl = 'https://securetoken.googleapis.com/v1/token';

  // ── Session state ─────────────────────────────────────────────────────
  String? _idToken;
  String? _refreshToken;
  String? _uid;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _refreshing;

  /// بيتنادى لما الجلسة تنتهى ومينفعش تتجدد (مثلاً الحساب اتعطّل).
  void Function()? onSessionExpired;

  String? get uid => _uid;
  String? get refreshToken => _refreshToken;
  bool get isSignedIn => _idToken != null;

  void signOut() {
    _idToken = null;
    _refreshToken = null;
    _uid = null;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ── Auth: sign in ─────────────────────────────────────────────────────
  Future<void> signIn(String email, String password) async {
    final res = await http.post(
      Uri.parse('$_authBase:signInWithPassword?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    _checkAuth(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _apply(
      uid: m['localId'] as String,
      idToken: m['idToken'] as String,
      refreshToken: m['refreshToken'] as String,
      expiresInSec: int.parse('${m['expiresIn']}'),
    );
  }

  /// يتأكد إن (إيميل + باسورد) صح ويرجّع الـ uid من غير ما يغيّر الجلسة الحالية.
  Future<String> verifyCredentials(String email, String password) async {
    final res = await http.post(
      Uri.parse('$_authBase:signInWithPassword?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': false,
      }),
    );
    _checkAuth(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['localId'] as String;
  }

  /// استرجاع الجلسة من refresh token محفوظ.
  Future<void> restore(String refreshToken) async {
    _refreshToken = refreshToken;
    try {
      await _refresh();
    } catch (_) {
      signOut();
      rethrow;
    }
  }

  // ── Auth: create account (لا يغيّر الجلسة الحالية) ────────────────────
  Future<String> createAuthAccount(String email, String password) async {
    final res = await http.post(
      Uri.parse('$_authBase:signUp?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': false,
      }),
    );
    _checkAuth(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['localId'] as String;
  }

  // ── Auth: change own password ─────────────────────────────────────────
  Future<void> changePassword(String newPassword) async {
    final token = await _token();
    final res = await http.post(
      Uri.parse('$_authBase:update?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': token,
        'password': newPassword,
        'returnSecureToken': true,
      }),
    );
    _checkAuth(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _apply(
      uid: _uid!,
      idToken: m['idToken'] as String,
      refreshToken: m['refreshToken'] as String,
      expiresInSec: int.parse('${m['expiresIn']}'),
    );
  }

  void _apply({
    required String uid,
    required String idToken,
    required String refreshToken,
    required int expiresInSec,
  }) {
    _uid = uid;
    _idToken = idToken;
    _refreshToken = refreshToken;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresInSec));
  }

  Future<String> _token() async {
    if (_idToken == null) {
      throw const ApiException(401, 'NOT_SIGNED_IN', 'سجّل الدخول أولاً');
    }
    if (DateTime.now().isBefore(_expiresAt.subtract(const Duration(minutes: 2)))) {
      return _idToken!;
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final rt = _refreshToken;
    if (rt == null) {
      throw const ApiException(401, 'NOT_SIGNED_IN', 'سجّل الدخول أولاً');
    }
    final res = await http.post(
      Uri.parse('$_tokenUrl?key=$_apiKey'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': rt},
    );
    if (res.statusCode != 200) {
      final hadSession = _idToken != null;
      signOut();
      if (hadSession) onSessionExpired?.call();
      throw const ApiException(
          401, 'SESSION_EXPIRED', 'انتهت الجلسة، سجّل الدخول من جديد');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _apply(
      uid: m['user_id'] as String,
      idToken: m['id_token'] as String,
      refreshToken: m['refresh_token'] as String,
      expiresInSec: int.parse('${m['expires_in']}'),
    );
    return _idToken!;
  }

  /// للتوافق مع الكود القديم: يتأكد إن فيه جلسة صالحة (ما بيعملش anonymous).
  Future<void> ensureAuth() async {
    await _token();
  }

  // ── Errors ────────────────────────────────────────────────────────────
  void _checkAuth(http.Response res) {
    if (res.statusCode == 200) return;
    String code = 'UNKNOWN';
    try {
      final body = jsonDecode(res.body);
      code = (body['error']['message'] as String).split(' ').first;
    } catch (_) {}
    final msg = switch (code) {
      'EMAIL_NOT_FOUND' ||
      'INVALID_PASSWORD' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        'بيانات الدخول غير صحيحة',
      'USER_DISABLED' => 'الحساب معطّل',
      'TOO_MANY_ATTEMPTS_TRY_LATER' =>
        'محاولات كتير غلط. حاول بعد شوية',
      'EMAIL_EXISTS' => 'الاسم + الكود مستخدمين بالفعل',
      'WEAK_PASSWORD' => 'كلمة المرور ضعيفة (6 حروف على الأقل)',
      'CREDENTIAL_TOO_OLD_LOGIN_AGAIN' => 'سجّل الدخول من جديد ثم أعد المحاولة',
      'OPERATION_NOT_ALLOWED' =>
        'تسجيل الدخول بالإيميل/الباسورد غير مفعّل فى Firebase Console',
      _ => 'تعذّر الاتصال بالخادم ($code)',
    };
    throw ApiException(res.statusCode, code, msg);
  }

  ApiException _fsError(http.Response res) {
    var detail = '';
    try {
      var body = jsonDecode(res.body);
      if (body is List && body.isNotEmpty) body = body.first;
      detail = (body['error']['message'] ?? '').toString();
    } catch (_) {}
    final msg = switch (res.statusCode) {
      401 => 'انتهت الجلسة، سجّل الدخول من جديد',
      403 => 'ليس لديك صلاحية لتنفيذ هذا الإجراء',
      404 => 'غير موجود',
      409 => 'السجل موجود بالفعل',
      _ => 'خطأ فى الخادم (${res.statusCode}) $detail',
    };
    return ApiException(res.statusCode, detail, msg);
  }

  // ── HTTP ──────────────────────────────────────────────────────────────
  Future<http.Response> _send(String method, Uri uri, {Object? body}) async {
    var res = await _once(method, uri, body, await _token());
    // 401 رغم إن التوكن شكله سليم (اتلغى من Firebase مثلاً): جدّده مرة واحدة وأعد
    // المحاولة. التجديد بالـ refresh token فقط — مفيش anonymous auth أبداً.
    if (res.statusCode == 401) {
      _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
      res = await _once(method, uri, body, await _token());
    }
    return res;
  }

  Future<http.Response> _once(
      String method, Uri uri, Object? body, String token) {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: body);
      case 'PATCH':
        return http.patch(uri, headers: headers, body: body);
      case 'DELETE':
        return http.delete(uri, headers: headers);
    }
    throw ArgumentError(method);
  }

  // ── GET Document ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getDoc(String path) async {
    final res = await _send('GET', Uri.parse('$_firestoreBase/$path'));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw _fsError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── SET Document (create/overwrite) ───────────────────────────────────
  Future<void> setDoc(String path, Map<String, dynamic> data) async {
    final res = await _send('PATCH', Uri.parse('$_firestoreBase/$path'),
        body: jsonEncode({'fields': _toFields(data)}));
    if (res.statusCode != 200) throw _fsError(res);
  }

  // ── UPDATE Document (partial fields) ──────────────────────────────────
  Future<void> updateDoc(String path, Map<String, dynamic> data) async {
    final mask = data.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    final res = await _send(
        'PATCH', Uri.parse('$_firestoreBase/$path?$mask&currentDocument.exists=true'),
        body: jsonEncode({'fields': _toFields(data)}));
    if (res.statusCode != 200) throw _fsError(res);
  }

  // ── ADD Document (auto ID) ────────────────────────────────────────────
  Future<String> addDoc(String collection, Map<String, dynamic> data) async {
    final res = await _send('POST', Uri.parse('$_firestoreBase/$collection'),
        body: jsonEncode({'fields': _toFields(data)}));
    if (res.statusCode != 200) throw _fsError(res);
    final name = (jsonDecode(res.body) as Map)['name'] as String;
    return name.split('/').last;
  }

  // ── DELETE Document ───────────────────────────────────────────────────
  Future<void> deleteDoc(String path) async {
    final res = await _send('DELETE', Uri.parse('$_firestoreBase/$path'));
    if (res.statusCode != 200) throw _fsError(res);
  }

  // ── COMMIT (atomic batch + server timestamps) ─────────────────────────
  Future<void> commit(List<WriteOp> ops) async {
    final writes = ops.map(_writeJson).toList();
    final res = await _send('POST', Uri.parse(_commitUrl),
        body: jsonEncode({'writes': writes}));
    if (res.statusCode != 200) throw _fsError(res);
  }

  Map<String, dynamic> _writeJson(WriteOp op) {
    final name = '$_dbName/${op.path}';
    if (op._delete) return {'delete': name};
    final w = <String, dynamic>{
      'update': {'name': name, 'fields': _toFields(op.data)},
    };
    if (op._merge) {
      w['updateMask'] = {'fieldPaths': op.data.keys.toList()};
      w['currentDocument'] = {'exists': true};
    }
    if (op._createOnly) w['currentDocument'] = {'exists': false};
    if (op.serverTimeFields.isNotEmpty) {
      w['updateTransforms'] = [
        for (final f in op.serverTimeFields)
          {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'}
      ];
    }
    return w;
  }

  // ── QUERY (structured query، شروط تساوى فقط) ──────────────────────────
  Future<List<Map<String, dynamic>>> listDocs(
    String collection, {
    Map<String, dynamic>? where,
    String? orderBy,
    int? limit,
  }) async {
    final filters = <Map<String, dynamic>>[];
    where?.forEach((key, value) {
      filters.add({
        'fieldFilter': {
          'field': {'fieldPath': key},
          'op': 'EQUAL',
          'value': _toValue(value),
        }
      });
    });

    final query = <String, dynamic>{
      'structuredQuery': {
        'from': [
          {'collectionId': collection}
        ],
        if (filters.isNotEmpty)
          'where': filters.length == 1
              ? filters.first
              : {
                  'compositeFilter': {'op': 'AND', 'filters': filters}
                },
        if (orderBy != null)
          'orderBy': [
            {
              'field': {'fieldPath': orderBy},
              'direction': 'DESCENDING'
            }
          ],
        if (limit != null) 'limit': limit,
      },
    };

    final res = await _send('POST', Uri.parse(_queryUrl), body: jsonEncode(query));
    if (res.statusCode != 200) throw _fsError(res);

    final results = jsonDecode(res.body) as List;
    return results
        .where((r) => r['document'] != null)
        .map((r) => r['document'] as Map<String, dynamic>)
        .toList();
  }

  // ── ID generator (زى Firestore auto-id) ───────────────────────────────
  String newId() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ── Helpers: Dart → Firestore ─────────────────────────────────────────
  Map<String, dynamic> _toFields(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k, _toValue(v)));
  }

  Map<String, dynamic> _toValue(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
    if (v is List) {
      return {
        'arrayValue': {'values': v.map(_toValue).toList()}
      };
    }
    if (v is Map) {
      return {
        'mapValue': {'fields': _toFields(Map<String, dynamic>.from(v))}
      };
    }
    return {'stringValue': '$v'};
  }

  // ── Helpers: Firestore → Dart ─────────────────────────────────────────
  static String docId(Map<String, dynamic> doc) =>
      (doc['name'] as String).split('/').last;

  static Map<String, dynamic> docData(Map<String, dynamic> doc) {
    final fields = doc['fields'] as Map<String, dynamic>? ?? {};
    return fields
        .map((k, v) => MapEntry(k, _fromValue(v as Map<String, dynamic>)));
  }

  static dynamic _fromValue(Map<String, dynamic> v) {
    if (v.containsKey('nullValue')) return null;
    if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
    if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
    if (v.containsKey('doubleValue')) {
      return (v['doubleValue'] as num).toDouble();
    }
    if (v.containsKey('stringValue')) return v['stringValue'] as String;
    if (v.containsKey('timestampValue')) {
      return DateTime.parse(v['timestampValue'] as String);
    }
    if (v.containsKey('arrayValue')) {
      final vals = (v['arrayValue'] as Map)['values'] as List? ?? [];
      return vals.map((e) => _fromValue(e as Map<String, dynamic>)).toList();
    }
    if (v.containsKey('mapValue')) {
      final fields =
          (v['mapValue'] as Map)['fields'] as Map<String, dynamic>? ?? {};
      return fields.map(
          (k, val) => MapEntry(k, _fromValue(val as Map<String, dynamic>)));
    }
    return null;
  }
}
